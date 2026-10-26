require "shiplog/version"
require "shiplog/classes"
require "shiplog/configuration"
require "shiplog/github/errors"
require "shiplog/github/queries"
require "shiplog/github/client"
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

    # Whether the host loaded Active Storage (its engine and the model macros). Screenshots need it; without it
    # every image feature stays off instead of failing.
    def active_storage? = !!(defined?(ActiveStorage::Engine) && ActiveRecord::Base.respond_to?(:has_many_attached))

    # Logged once at boot (see Shiplog::Engine): screenshots wanted but Active Storage missing.
    def log_images_status
      return unless config.images && !active_storage?

      Rails.logger&.info("[shiplog] Screenshots are off: Active Storage is not loaded. Require active_storage/engine to enable them.")
    end

    # Whether screenshots are in use: config.images and Active Storage.
    def images? = config.images && active_storage?
  end
end
