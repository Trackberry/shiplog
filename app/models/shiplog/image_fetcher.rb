module Shiplog
  # Attaches the screenshots of a draft's GitHub issue or pull request to the entry. Runs when a draft is
  # written (Shiplog::RewriteEntryJob), only for a draft without images: an approved entry's images are never
  # changed automatically. Every failure (GitHub, network, validation) is logged and skipped; it never raises.
  class ImageFetcher
    # Seconds for all the images of one entry together; the rest are skipped (and logged) once it is spent.
    FETCH_BUDGET = 45

    def self.call(entry) = new(entry).call

    def initialize(entry)
      @entry = entry
    end

    # Returns how many images were attached.
    def call
      return 0 unless eligible?

      html = body_html
      urls = Sources.urls(html, limit: Shiplog.config.max_images_per_entry)
      return 0 if urls.empty?

      files = download_all(urls)
      files.empty? ? 0 : attach(files)
    rescue StandardError => error
      Rails.logger&.warn("[shiplog] Fetching images for entry #{@entry.id} failed: #{error.class}: #{error.message}")
      0
    end

    private

    # The files of the URLs that downloaded, in order. Once FETCH_BUDGET seconds are spent, the rest are skipped.
    def download_all(urls)
      downloader = Downloader.new(token: Shiplog.config.resolved_github_token)
      started = Downloader.now
      files = []
      urls.each_with_index do |url, index|
        remaining = FETCH_BUDGET - (Downloader.now - started)
        if remaining <= 0
          Rails.logger&.warn("[shiplog] Entry #{@entry.id}: the image budget of #{FETCH_BUDGET}s is spent, skipped #{urls.size - index} remaining image(s)")
          break
        end

        download = downloader.call(url, budget: remaining)
        files << file_for(download, index) if download
      end
      files
    end

    def file_for(download, index)
      { io: StringIO.new(download.body), filename: "screenshot-#{index + 1}.#{ImageType::EXTENSIONS.fetch(download.content_type)}",
        content_type: download.content_type, metadata: { width: download.width, height: download.height } }
    end

    def eligible?
      Shiplog.images? && Shiplog.config.max_images_per_entry.positive? && @entry.draft? &&
        Entry::CHANGELOG_KINDS.include?(@entry.kind) && !@entry.images.attached? && node_id.present?
    end

    def node_id = @entry.subject.try(:node_id)

    def body_html
      Github::Client.new.query(Github::Queries::BODY_HTML, id: node_id).dig("node", "bodyHTML")
    end

    # Uploaded before the entry's row lock is taken; under the lock, so two jobs cannot both attach, the state is
    # checked again (still a draft, still without images), otherwise the uploaded blobs are purged.
    def attach(files)
      @entry.add_images(files) { @entry.draft? && !@entry.images.attached? }.size
    end
  end
end
