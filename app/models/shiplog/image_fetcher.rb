module Shiplog
  # Attaches the screenshots of a draft's GitHub issue or pull request to the entry. Runs when a draft is
  # written (Shiplog::RewriteEntryJob), only for a draft without images: an approved entry's images are never
  # changed automatically. Every failure (GitHub, network, validation) is logged and skipped; it never raises.
  class ImageFetcher
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

      downloader = Downloader.new(token: Shiplog.config.resolved_github_token)
      files = urls.each_with_index.filter_map do |url, index|
        download = downloader.call(url)
        download && { io: StringIO.new(download.body), filename: "screenshot-#{index + 1}.#{ImageType::EXTENSIONS.fetch(download.content_type)}", content_type: download.content_type }
      end
      files.empty? ? 0 : attach(files)
    rescue StandardError => error
      Rails.logger&.warn("[shiplog] Fetching images for entry #{@entry.id} failed: #{error.class}: #{error.message}")
      0
    end

    private

    def eligible?
      Shiplog.images? && Shiplog.config.max_images_per_entry.positive? && @entry.draft? &&
        Entry::CHANGELOG_KINDS.include?(@entry.kind) && !@entry.images.attached? && node_id.present?
    end

    def node_id = @entry.subject.try(:node_id)

    def body_html
      Github::Client.new.query(Github::Queries::BODY_HTML, id: node_id).dig("node", "bodyHTML")
    end

    # Under the entry's row lock, so two jobs cannot both attach; the state is checked again there.
    def attach(files)
      @entry.with_lock do
        next 0 unless @entry.draft? && !@entry.images.attached?

        @entry.add_images(files).size
      end
    end
  end
end
