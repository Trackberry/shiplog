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

    # after_action of the changelog index and the permalink pages: calls config.on_changelog_seen for a visit
    # that got the page (200) or was told it is unchanged (304, a revisit is a visit). Not for 404s or the feed.
    # The response is not sent yet, so the callback can still set cookies or headers. A failing callback is
    # logged and never breaks the page.
    def notify_changelog_seen
      callback = Shiplog.config.on_changelog_seen
      return unless callback && [ 200, 304 ].include?(response.status) && request.format.html?

      callback.call(self)
    rescue StandardError => error
      Rails.logger.error("[shiplog] on_changelog_seen failed: #{error.class}: #{error.message}")
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

    # What the rendered markup depends on besides the data: the locale, the gem version and the styling
    # config. Host parent controllers rendering per-user layout content should declare `etag { current_user&.id }`.
    def shiplog_etag_parts
      [ I18n.locale, Shiplog::VERSION, Shiplog.config.render_digest ]
    end
  end
end
