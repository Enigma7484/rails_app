require "faraday"
require "faraday/multipart"
require "tempfile"
require "csv"
require "json"
require "securerandom"
require "time"

class UploadsController < ApplicationController
  before_action :authenticate_user!

  def index
    @uploads = current_user.uploads.order(created_at: :desc)
    @selected_upload_id = params[:upload_id].presence

    if @selected_upload_id.present? && !@uploads.exists?(id: @selected_upload_id)
      @selected_upload_id = nil
    end

    subscriptions_scope = Subscription.joins(:upload).where(uploads: { user_id: current_user.id })
    subscriptions_scope = subscriptions_scope.where(upload_id: @selected_upload_id) if @selected_upload_id.present?

    @subscriptions = subscriptions_scope
    @category_spend = @subscriptions.group(:category).sum(:avg_amount).transform_keys { |k| k.presence || "Uncategorized" }
    @frequency_counts = @subscriptions.group(:frequency).count.transform_keys { |k| k.presence || "Unknown" }
    @trend_by_upload_date = @subscriptions.joins(:upload).group("DATE(uploads.created_at)").sum(:avg_amount)
    @total_monthly = @subscriptions.where(frequency: "monthly").sum(:avg_amount)
    @total_count = @subscriptions.count
    @top_category = @category_spend.max_by { |_k, v| v }&.first
    @upcoming_subscriptions = @subscriptions
      .where.not(next_expected: nil)
      .where(next_expected: Date.current..30.days.from_now.to_date)
      .where.not(status: "ignored")
      .order(:next_expected)
    @upcoming_7_day_total = @upcoming_subscriptions
      .where(next_expected: Date.current..7.days.from_now.to_date)
      .sum(:avg_amount)
    @upcoming_30_day_total = @upcoming_subscriptions.sum(:avg_amount)
  end

  def new
    @upload = Upload.new
  end

  def new_manual
  end

  def create
    @upload = current_user.uploads.new
    @upload.file.attach(params[:upload][:file]) if params[:upload] && params[:upload][:file]

    if @upload.save
      redirect_to @upload, notice: "File uploaded successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def analyze_manual
    rows = parse_manual_rows(params[:transactions].to_s)

    if rows.empty?
      redirect_to new_manual_upload_path, alert: "Add at least one transaction in the format YYYY-MM-DD Merchant Amount Currency."
      return
    end

    connection = Faraday.new(url: ENV.fetch("AGENT_SERVICE_URL")) do |f|
      f.request :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end

    response = connection.post("/analyze-rows") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { rows: rows }
    end

    parsed = JSON.parse(response.body)
    upload = current_user.uploads.create!(analysis_result: parsed)
    if parsed["error"].present?
      redirect_to upload, alert: "Manual analysis completed with an error: #{parsed["error"]}"
      return
    end

    persist_subscriptions!(upload)

    redirect_to upload, notice: "Manual transactions analyzed successfully."
  rescue => e
    redirect_to new_manual_upload_path, alert: "Error while analyzing manual transactions: #{e.message}"
  end

  def show
    @upload = current_user.uploads.find(params[:id])
    @persisted_subscriptions = @upload.subscriptions
  end

  def destroy
    @upload = current_user.uploads.find(params[:id])
    @upload.destroy!
    redirect_to uploads_path, notice: "Upload deleted successfully.", status: :see_other
  end

  def analyze
    @upload = current_user.uploads.find(params[:id])

    unless @upload.file.attached?
      redirect_to @upload, alert: "No file attached."
      return
    end

    filename = @upload.file.filename.to_s
    content_type = @upload.file.content_type || "text/csv"
    tempfile = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    tempfile.binmode
    tempfile.write(@upload.file.download)
    tempfile.rewind

    connection = Faraday.new(url: ENV.fetch("AGENT_SERVICE_URL")) do |f|
      f.request :multipart
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    response = connection.post("/analyze") do |req|
      req.body = {
        file: Faraday::Multipart::FilePart.new(tempfile.path, content_type, filename)
      }
    end

    if response.success?
      parsed = JSON.parse(response.body)
      @upload.update!(analysis_result: parsed)
      if parsed["error"].present?
        redirect_to @upload, alert: "Analysis completed with an error: #{parsed["error"]}"
        return
      end

      persist_subscriptions!(@upload)
      redirect_to @upload, notice: "Analysis completed."
    else
      redirect_to @upload, alert: "Analysis failed. Agent service returned #{response.status}."
    end
  rescue => e
    redirect_to @upload, alert: "Error while analyzing file: #{e.message}"
  ensure
    tempfile&.close
    tempfile&.unlink
  end

  def update_parsed_row
    @upload = current_user.uploads.find(params[:id])

    unless @upload.analysis_result.present?
      redirect_to @upload, alert: "No analysis data found."
      return
    end

    parsed_rows = @upload.analysis_result["parsed_rows"] || []
    row_index = params[:row_index].to_i

    if row_index.negative? || row_index >= parsed_rows.length
      redirect_to @upload, alert: "Invalid row index."
      return
    end

    canonical_name = params[:merchant_normalized].to_s.strip
    raw_name = parsed_rows[row_index]["merchant"].to_s.strip
    parsed_rows[row_index]["merchant_normalized"] = canonical_name
    remember_merchant_alias(raw_name, canonical_name)

    updated_result = @upload.analysis_result || {}
    updated_result["parsed_rows"] = parsed_rows
    @upload.update!(analysis_result: updated_result)

    redirect_to @upload, notice: "Parsed row updated successfully."
  end

  def recalculate
    @upload = current_user.uploads.find(params[:id])

    unless @upload.analysis_result.present?
      redirect_to @upload, alert: "No analysis data found."
      return
    end

    parsed_rows = apply_user_aliases(@upload.analysis_result["parsed_rows"] || [])

    connection = Faraday.new(url: ENV.fetch("AGENT_SERVICE_URL")) do |f|
      f.request :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end

    response = connection.post("/recalculate") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { parsed_rows: parsed_rows }
    end

    parsed = JSON.parse(response.body)
    updated_result = @upload.analysis_result || {}
    updated_result["subscriptions"] = parsed["subscriptions"] || []
    updated_result["needs_review"] = parsed["needs_review"] || []
    updated_result["parsed_rows"] = parsed["parsed_rows"] || parsed_rows
    updated_result["row_count"] = parsed["row_count"] || parsed_rows.length
    updated_result["warnings"] = parsed["warnings"] || []
    updated_result["error"] = parsed["error"] || ""

    @upload.update!(analysis_result: updated_result)
    persist_subscriptions!(@upload)

    redirect_to @upload, notice: "Subscriptions recalculated successfully."
  rescue => e
    redirect_to @upload, alert: "Error while recalculating: #{e.message}"
  end

  def export_subscriptions_csv
    @upload = current_user.uploads.find(params[:id])
    subscriptions = (@upload.analysis_result || {})["subscriptions"] || []

    csv_data = CSV.generate(headers: true) do |csv|
      csv << [
        "merchant",
        "merchant_normalized",
        "category",
        "bill_type",
        "frequency",
        "avg_amount",
        "last_paid",
        "next_expected",
        "confidence",
        "description",
        "evidence_summary"
      ]

      subscriptions.each do |sub|
        csv << [
          sub["merchant"],
          sub["merchant_normalized"],
          sub["category"],
          sub["bill_type"],
          sub["frequency"],
          sub["avg_amount"],
          sub["last_paid"],
          sub["next_expected"],
          sub["confidence"],
          sub["description"],
          sub["evidence_summary"] || sub["evidence"]
        ]
      end
    end

    send_data csv_data, filename: "subscriptions_upload_#{@upload.id}.csv", type: "text/csv"
  end

  def export_calendar
    @upload = current_user.uploads.find(params[:id])
    subscriptions = (@upload.analysis_result || {})["subscriptions"] || []

    ics_lines = []
    ics_lines << "BEGIN:VCALENDAR"
    ics_lines << "VERSION:2.0"
    ics_lines << "PRODID:-//BillsAgent//Subscriptions//EN"

    subscriptions.each do |sub|
      next unless sub["next_expected"].present?

      begin
        start_date = Date.parse(sub["next_expected"])
      rescue StandardError
        next
      end

      freq =
        case sub["frequency"].to_s.downcase
        when "weekly" then "WEEKLY"
        when "biweekly" then nil
        when "monthly" then "MONTHLY"
        when "quarterly" then "MONTHLY;INTERVAL=3"
        when "yearly" then "YEARLY"
        else nil
        end

      uid = "#{SecureRandom.uuid}@bills-agent"
      dtstamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      dtstart = start_date.strftime("%Y%m%d")
      summary = "Recurring charge: #{sub["merchant"]}"
      description = [
        "Normalized: #{sub["merchant_normalized"]}",
        "Category: #{sub["category"]}",
        "Bill type: #{sub["bill_type"]}",
        "Amount: #{sub["avg_amount"]}",
        "Confidence: #{sub["confidence"]}",
        "Evidence: #{sub["evidence_summary"] || sub["evidence"]}"
      ].join("\\n")

      ics_lines << "BEGIN:VEVENT"
      ics_lines << "UID:#{uid}"
      ics_lines << "DTSTAMP:#{dtstamp}"
      ics_lines << "DTSTART;VALUE=DATE:#{dtstart}"
      ics_lines << "SUMMARY:#{summary}"
      ics_lines << "DESCRIPTION:#{description}"
      ics_lines << "RRULE:FREQ=#{freq}" if freq&.exclude?(";")
      ics_lines << "RRULE:#{freq}" if freq&.include?(";")
      ics_lines << "END:VEVENT"
    end

    ics_lines << "END:VCALENDAR"
    send_data ics_lines.join("\r\n"), filename: "subscription_reminders_upload_#{@upload.id}.ics", type: "text/calendar"
  end

  def enrich_subscriptions
    @upload = current_user.uploads.find(params[:id])

    unless @upload.analysis_result.present?
      redirect_to @upload, alert: "No analysis data found."
      return
    end

    subscriptions = @upload.analysis_result["subscriptions"] || []

    connection = Faraday.new(url: ENV.fetch("AGENT_SERVICE_URL")) do |f|
      f.request :json
      f.response :raise_error
      f.adapter Faraday.default_adapter
    end

    response = connection.post("/enrich") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { subscriptions: subscriptions }
    end

    parsed = JSON.parse(response.body)
    updated_result = @upload.analysis_result || {}
    updated_result["subscriptions"] = parsed["subscriptions"] || subscriptions
    updated_result["warnings"] = parsed["warnings"] || []
    updated_result["enrichment_error"] = parsed["error"] if parsed.key?("error")

    @upload.update!(analysis_result: updated_result)
    persist_subscriptions!(@upload)

    redirect_to @upload, notice: "Subscriptions enriched successfully."
  rescue => e
    redirect_to @upload, alert: "Error while enriching subscriptions: #{e.message}"
  end

  private

  def persist_subscriptions!(upload)
    previous_statuses = upload.subscriptions.each_with_object({}) do |subscription, statuses|
      statuses[subscription_key(subscription)] = {
        status: subscription.status,
        user_note: subscription.user_note
      }
    end

    upload.subscriptions.destroy_all
    subscriptions = (upload.analysis_result || {})["subscriptions"] || []

    subscriptions.each do |sub|
      previous = previous_statuses[subscription_key(sub)] || {}

      upload.subscriptions.create!(
        merchant: sub["merchant"],
        merchant_normalized: sub["merchant_normalized"],
        category: sub["category"],
        bill_type: sub["bill_type"],
        description: sub["description"],
        frequency: sub["frequency"],
        avg_amount: sub["avg_amount"],
        last_paid: sub["last_paid"],
        next_expected: sub["next_expected"],
        confidence: sub["confidence"],
        evidence: sub["evidence"].is_a?(Hash) ? sub["evidence"].to_json : sub["evidence"],
        evidence_summary: sub["evidence_summary"],
        status: previous[:status] || "detected",
        user_note: previous[:user_note]
      )
    end
  end

  def apply_user_aliases(rows)
    aliases = current_user.merchant_aliases.to_a

    rows.map do |row|
      matched = aliases.find do |alias_record|
        raw_name = alias_record.raw_name.to_s.downcase
        row["merchant"].to_s.downcase.include?(raw_name) ||
          row["merchant_normalized"].to_s.downcase == raw_name
      end

      row["merchant_normalized"] = matched.canonical_name if matched
      row
    end
  end

  def parse_manual_rows(text)
    text.lines.filter_map do |line|
      match = line.strip.match(
        /\A(?<date>\d{4}-\d{2}-\d{2})\s+(?<merchant>.+?)\s+(?<amount>-?\$?\d+(?:,\d{3})*(?:\.\d{1,2})?)\s*(?<currency>[A-Za-z]{3})?\z/
      )
      next unless match

      {
        date: match[:date],
        merchant: match[:merchant].strip,
        amount: match[:amount].delete("$,").to_f,
        currency: match[:currency].presence || "CAD"
      }
    end
  end

  def remember_merchant_alias(raw_name, canonical_name)
    return if raw_name.blank? || canonical_name.blank?

    alias_record = current_user.merchant_aliases.find_or_initialize_by(raw_name: raw_name)
    alias_record.canonical_name = canonical_name
    alias_record.save!
  end

  def subscription_key(subscription)
    merchant = subscription.respond_to?(:merchant_normalized) ? subscription.merchant_normalized : subscription["merchant_normalized"]
    amount = subscription.respond_to?(:avg_amount) ? subscription.avg_amount : subscription["avg_amount"]

    [
      merchant.to_s.downcase.strip,
      format("%.2f", amount.to_f)
    ].join("|")
  end
end
