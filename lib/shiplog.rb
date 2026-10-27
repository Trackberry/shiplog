require "shiplog/version"
require "shiplog/classes"
require "shiplog/configuration"
require "shiplog/github/errors"
require "shiplog/github/queries"
require "shiplog/github/client"
require "shiplog/head_tags_helper"
require "shiplog/engine"
require "shiplog/admin/engine"

module Shiplog
  class << self
    def config = (@config ||= Configuration.new)
    def configure = yield(config)
    def reset_config! = (@config = nil)

    # The number of approved features and changes approved after `since`, or all of them while it is nil, capped
    # at 99. Counted on approved_at (when the entry was approved), not released_on (the list's order). The host supplies the timestamp (Shiplog doesn't know its users): see config.on_changelog_seen.
    def unseen_count(since: nil) = Entry.unseen_count(since:)

    # The number of approved monthly announcements approved after `since` (all of them while it is nil), capped
    # at 99: the rare "what's new" signal, where unseen_count counts every daily entry. 0 while announcements are off.
    def unseen_announcements_count(since: nil) = announcements? ? Entry.unseen_announcements_count(since:) : 0

    # Whether monthly announcements are on (config.announcements is :page or :external).
    def announcements? = config.announcements != false

    # Whether Shiplog renders announcement pages (config.announcements is :page).
    def announcement_pages? = config.announcements == :page

    # Whether the newsletter is on: config.newsletter, and announcements (there is nothing else to send).
    def newsletter? = config.newsletter && announcements?

    # Logged once at boot (see Shiplog::Engine), while the newsletter is on: what keeps it from sending, a
    # recipients callable without the unsubscribe hook (unsubscribes would not reach the host's list), and a
    # cache that counts nothing (the subscribe form's rate limits are then off).
    def log_newsletter_status
      return unless newsletter?

      missing = []
      missing << "newsletter_from" if Newsletter.from.blank?
      missing << "newsletter_address" if config.newsletter_address.blank?
      missing << "canonical_url (or action_mailer.default_url_options)" if Newsletter.base_url.blank?
      Rails.logger&.warn("[shiplog] config.newsletter is on, but the newsletter cannot be sent until these are set: #{missing.join(", ")}.") if missing.any?
      if config.newsletter_recipients && config.on_newsletter_unsubscribe.nil?
        Rails.logger&.warn("[shiplog] config.newsletter_recipients is set but config.on_newsletter_unsubscribe is not: Shiplog suppresses an address that unsubscribes, but your own list will not know.")
      end
      if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
        Rails.logger&.warn("[shiplog] Rails.cache is a null store, so the newsletter's subscribe form is not rate limited. Configure a cache store.")
      end
    end

    ACTIVE_STORAGE_TABLES = %w[active_storage_attachments active_storage_blobs].freeze

    # Whether the host loaded Active Storage (its engine and the model macros). The declaration on Entry needs
    # only this, so it never touches the database.
    def active_storage_loaded? = !!(defined?(ActiveStorage::Engine) && ActiveRecord::Base.respond_to?(:has_many_attached))

    # Whether screenshots can work: Active Storage is loaded and its tables exist (a host that loads
    # `rails/all` but never ran active_storage:install would otherwise fail on every query). Without either,
    # every image feature stays off instead of failing.
    def active_storage? = active_storage_loaded? && active_storage_tables?

    # Whether the Active Storage tables exist. Checked lazily, on first use, then remembered for the life of the
    # process, so public pages never look at the schema again. When the database can't be reached (at boot, say)
    # the answer is "not yet known": false for now, and asked again next time. The reason is logged once.
    def active_storage_tables?
      return @active_storage_tables unless @active_storage_tables.nil?

      present = ActiveRecord::Base.with_connection { |connection| ACTIVE_STORAGE_TABLES.all? { |table| connection.data_source_exists?(table) } }
      log_images_off("Active Storage's tables are missing (#{ACTIVE_STORAGE_TABLES.join(", ")}). Run bin/rails active_storage:install and db:migrate to enable them.") unless present || !config.images
      @active_storage_tables = present
    rescue ActiveRecord::ActiveRecordError
      false
    end

    # Forgets what was learned about the schema and what was logged (tests, and hosts that create the tables at runtime).
    def reset_images_checks!
      @active_storage_tables = nil
      @images_off_logged = nil
      @image_variants = nil
    end

    # Logged once at boot (see Shiplog::Engine): screenshots wanted but Active Storage missing. A missing
    # table is logged by the check itself, the first time it runs.
    def log_images_status
      return unless config.images

      if !active_storage_loaded? then log_images_off("Active Storage is not loaded. Require active_storage/engine to enable them.")
      else active_storage_tables?
      end
    end

    # Whether the admin can show thumbnails as variants: the image_processing gem is loaded and so is a
    # processor for it (ruby-vips, which must load, or mini_magick). Otherwise the originals are shown.
    def image_variants?
      return @image_variants unless @image_variants.nil?

      @image_variants = Gem.loaded_specs.key?("image_processing") && (vips_loads? || Gem.loaded_specs.key?("mini_magick"))
    end

    # Whether screenshots are in use: config.images and Active Storage.
    def images? = config.images && active_storage?

    private

    def vips_loads?
      return true if defined?(::Vips)

      Gem.loaded_specs.key?("ruby-vips") && require("vips")
    rescue LoadError
      false
    end

    def log_images_off(reason)
      @images_off_logged ||= Set.new
      return unless @images_off_logged.add?(reason)

      Rails.logger&.info("[shiplog] Screenshots are off: #{reason}")
    end
  end
end
