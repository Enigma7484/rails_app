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

    if @selected_upload_id.present?
      subscriptions_scope = subscriptions_scope.where(upload_id: @selected_upload_id)
    end

    @subscriptions = subscriptions_scope

    @category_spend = @subscriptions
      .group(:category)
      .sum(:avg_amount)
      .transform_keys { |k| k.presence || "Uncategorized" }

    @frequency_counts = @subscriptions
      .group(:frequency)
      .count
      .transform_keys { |k| k.presence || "Unknown" }

    @trend_by_upload_date = @subscriptions
      .joins(:upload)
      .group("DATE(uploads.created_at)")
      .sum(:avg_amount)

    @total_monthly = @subscriptions.where(frequency: "monthly").sum(:avg_amount)
    @total_count = @subscriptions.count
    @top_category = @category_spend.max_by { |_k, v| v }&.first
  end
  
  def new
    @upload = Upload.new
  end

  def create
    @upload = current_user.uploads.new

    if params[:upload] && params[:upload][:file]
      @upload.file.attach(params[:upload][:file])
    end

    if @upload.save
      redirect_to @upload, notice: "File uploaded successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @upload = current_user.uploads.find(params[:id])
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

    downloaded_file = @upload.file.download
    filename = @upload.file.filename.to_s
    content_type = @upload.file.content_type || "text/csv"

    tempfile = Tempfile.new([File.basename(filename, ".*"), File.extname(filename)])
    tempfile.binmode
    tempfile.write(downloaded_file)
    tempfile.rewind

    connection = Faraday.new(url: ENV.fetch("AGENT_SERVICE_URL")) do |f|
      f.request :multipart
      f.request :url_encoded
      f.adapter Faraday.default_adapter
    end

    response = connection.post("/analyze") do |req|
      req.body = {
        file: Faraday::Multipart::FilePart.new(
          tempfile.path,
          content_type,
          filename
        )
      }
    end

    if response.success?
      parsed = JSON.parse(response.body)
      @upload.update!(analysis_result: parsed)
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

  if row_index < 0 || row_index >= parsed_rows.length
    redirect_to @upload, alert: "Invalid row index."
    return
  end

  parsed_rows[row_index]["merchant_normalized"] = params[:merchant_normalized].to_s.strip

  updated_result = @upload.analysis_result
  updated_result["parsed_rows"] = parsed_rows

  @upload.update!(analysis_result: updated_result)
  persist_subscriptions!(@upload)

  redirect_to @upload, notice: "Parsed row updated successfully."
end

def recalculate
  @upload = current_user.uploads.find(params[:id])

  unless @upload.analysis_result.present?
    redirect_to @upload, alert: "No analysis data found."
    return
  end

  parsed_rows = @upload.analysis_result["parsed_rows"] || []

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

  updated_result = @upload.analysis_result
  updated_result["subscriptions"] = parsed["subscriptions"] || []
  updated_result["needs_review"] = parsed["needs_review"] || []
  updated_result["parsed_rows"] = parsed["parsed_rows"] || parsed_rows
  updated_result["row_count"] = parsed["row_count"] || parsed_rows.length
  updated_result["error"] = parsed["error"] if parsed.key?("error")

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
      "frequency",
      "avg_amount",
      "last_paid",
      "next_expected",
      "confidence",
      "evidence"
    ]

    subscriptions.each do |sub|
      csv << [
        sub["merchant"],
        sub["merchant_normalized"],
        sub["frequency"],
        sub["avg_amount"],
        sub["last_paid"],
        sub["next_expected"],
        sub["confidence"],
        sub["evidence"]
      ]
    end
  end

  send_data csv_data,
            filename: "subscriptions_upload_#{@upload.id}.csv",
            type: "text/csv"
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
    rescue
      next
    end

    freq =
      case sub["frequency"].to_s.downcase
      when "weekly"
        "WEEKLY"
      when "monthly"
        "MONTHLY"
      when "yearly"
        "YEARLY"
      else
        nil
      end

    uid = "#{SecureRandom.uuid}@bills-agent"
    dtstamp = Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
    dtstart = start_date.strftime("%Y%m%d")

    summary = "Subscription charge: #{sub["merchant"]}"
    description = [
      "Normalized: #{sub["merchant_normalized"]}",
      "Amount: #{sub["avg_amount"]}",
      "Confidence: #{sub["confidence"]}",
      "Evidence: #{sub["evidence"]}"
    ].join("\\n")

    ics_lines << "BEGIN:VEVENT"
    ics_lines << "UID:#{uid}"
    ics_lines << "DTSTAMP:#{dtstamp}"
    ics_lines << "DTSTART;VALUE=DATE:#{dtstart}"
    ics_lines << "SUMMARY:#{summary}"
    ics_lines << "DESCRIPTION:#{description}"
    ics_lines << "RRULE:FREQ=#{freq}" if freq
    ics_lines << "END:VEVENT"
  end

  ics_lines << "END:VCALENDAR"

  send_data ics_lines.join("\r\n"),
            filename: "subscription_reminders_upload_#{@upload.id}.ics",
            type: "text/calendar"
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

  updated_result = @upload.analysis_result
  updated_result["subscriptions"] = parsed["subscriptions"] || subscriptions
  updated_result["enrichment_error"] = parsed["error"] if parsed.key?("error")

  @upload.update!(analysis_result: updated_result)
  persist_subscriptions!(@upload)
  
  redirect_to @upload, notice: "Subscriptions enriched successfully."
rescue => e
  redirect_to @upload, alert: "Error while enriching subscriptions: #{e.message}"
end

private

def persist_subscriptions!(upload)
  upload.subscriptions.destroy_all

  subscriptions = (upload.analysis_result || {})["subscriptions"] || []

  subscriptions.each do |sub|
    upload.subscriptions.create!(
      merchant: sub["merchant"],
      merchant_normalized: sub["merchant_normalized"],
      category: sub["category"],
      description: sub["description"],
      frequency: sub["frequency"],
      avg_amount: sub["avg_amount"],
      last_paid: sub["last_paid"],
      next_expected: sub["next_expected"],
      confidence: sub["confidence"],
      evidence: sub["evidence"]
    )
  end
end

end