module Shiplog
  # Parent controller for the public pages. The parent class is resolved when this
  # file loads, so `config.public_parent_controller` must be set in an initializer
  # (config/initializers/shiplog.rb), not later at runtime.
  class PublicController < Shiplog.config.public_parent_controller.constantize
    helper Shiplog::FrontendHelper
    helper Shiplog::StylingHelper
    helper Shiplog::SwitcherHelper
    helper Shiplog::RoadmapHelper
    helper Shiplog::HostRoutesHelper
    helper Shiplog::PermalinkHelper
    layout -> { Shiplog.config.public_layout }

    private

    # Calls config.on_changelog_seen for a visit to the changelog index or a permalink page. It runs before
    # the page renders (the actions call it once they know the page exists, ahead of fresh_when and the
    # implicit render), so a host navbar badge in the same response shows the count the callback just stored,
    # also when the answer ends up a 304 (a revisit is a visit). Not called for 404s or the feed.
    # The response is not sent yet, so the callback can still set cookies or headers. A failing callback is
    # logged and never breaks the page.
    def notify_changelog_seen
      callback = Shiplog.config.on_changelog_seen
      return unless callback && request.format.html?

      callback.call(self)
    rescue StandardError => error
      Rails.logger.error("[shiplog] on_changelog_seen failed: #{error.class}: #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}")
    end

    # Sets @area from ?area=<slug>. A blank or non-string value is ignored; a slug no area has is a 404 (a
    # renamed or deleted area has no page to show, rather than the unfiltered list under a filtered URL).
    def set_area
      slug = params[:area]
      return unless slug.is_a?(String) && slug.present?

      @area = Area.find_by(slug:)
      head(:not_found) unless @area
    end

    # What the markup shows of the areas: names, slugs and order of every area (the tags and the filter), which
    # entries' updated_at don't reflect when an area is renamed or entries are moved in bulk.
    def shiplog_area_etag_parts
      [ @area&.id, Area.ordered.pluck(:id, :name, :slug, :position) ]
    end

    # What the markup shows of the entries' screenshots: their blob ids, order and alt texts. Nothing while
    # screenshots are off. Load the entries with `Entry.with_images_loaded` to avoid a query per entry.
    def shiplog_image_etag_parts(entries)
      Shiplog.images? ? entries.compact.map { |entry| [ entry.id, entry.image_etag_parts ] } : []
    end

    # Loads the translations the page shows (the request locale's) for these entries in one query; see
    # Entry.preload_translations. Call it before the entries are rendered or their ETag is computed.
    def preload_translations(*entries)
      Entry.preload_translations(entries.flatten)
    end

    # What the markup shows of the entries' translations: which current translation each entry shows, and when
    # it last changed. Nothing under a locale that is not translated.
    def shiplog_translation_etag_parts(entries)
      return [] unless Entry.translated_locale?(I18n.locale)

      entries.compact.filter_map do |entry|
        translation = entry.translation
        [ entry.id, translation.id, translation.updated_at ] if translation
      end
    end

    # What the rendered markup depends on besides the data: the locale, the gem version and the styling
    # config. Host parent controllers rendering per-user layout content should declare `etag { current_user&.id }`.
    def shiplog_etag_parts
      [ I18n.locale, Shiplog::VERSION, Shiplog.config.render_digest ]
    end
  end
end
