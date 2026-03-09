require "faraday"
require "faraday/multipart"
require "json"
require "tempfile"

class UploadsController < ApplicationController
  def new
    @upload = Upload.new
  end

  def create
    @upload = Upload.new

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
    @upload = Upload.find(params[:id])
  end

  def analyze
    @upload = Upload.find(params[:id])

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

    connection = Faraday.new(url: "http://localhost:8000") do |f|
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
end