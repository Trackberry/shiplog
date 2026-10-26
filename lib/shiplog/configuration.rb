module Shiplog
  class Configuration
    attr_accessor :github_token, :webhook_secret,
      :public_label, :soon_labels, :excluded_labels, :excluded_authors, :commit_types,
      :rewriter, :product_name, :audience, :tone, :prompt_builder,
      :public_layout, :admin_layout,
      :stylesheet, :admin_flash, :authorize_admin, :current_admin,
      :roadmap_path, :changelog_path

    ADMIN_CHROMES = %i[standalone hosted].freeze
    REPOSITORY_OPTION_KEYS = %i[name changelog gem].freeze

    attr_reader :repositories
    # Path of the lockfile read in merged pull requests to detect gem upgrades (see config.repositories `gem:`).
    attr_accessor :lockfile_path

    attr_reader :admin_chrome, :classes, :public_parent_controller, :admin_parent_controller

    # :standalone (default) wraps the admin in Shiplog's own page chrome; :hosted renders it inside the
    # layout of config.admin_layout (compact sub-nav, no page chrome of its own).
    def admin_chrome=(value)
      chrome = value.to_s.to_sym if value.respond_to?(:to_sym)
      unless ADMIN_CHROMES.include?(chrome)
        raise ArgumentError, "Invalid admin_chrome #{value.inspect}. Valid values: #{ADMIN_CHROMES.map(&:inspect).join(", ")}"
      end
      @admin_chrome = chrome
    end

    # Extra classes per element (see Shiplog::Classes::KEYS). Unknown keys raise in every environment;
    # string keys become symbols and the hash is stored as a frozen copy.
    def classes=(value)
      classes = (value || {}).to_h.transform_keys { |key| key.to_s.to_sym }
      unknown = classes.keys - Shiplog::Classes::KEYS
      if unknown.any?
        raise ArgumentError, "Unknown Shiplog classes key(s): #{unknown.map(&:inspect).join(", ")}. " \
          "Valid keys: #{Shiplog::Classes::KEYS.map(&:inspect).join(", ")}"
      end
      @classes = classes.freeze
    end

    # The parent classes are read once, when the engine's controllers load.
    def public_parent_controller=(value)
      ensure_controller_not_loaded!(:public_parent_controller, Shiplog, :PublicController)
      @public_parent_controller = value
    end

    def admin_parent_controller=(value)
      ensure_controller_not_loaded!(:admin_parent_controller, Shiplog::Admin, :ApplicationController)
      @admin_parent_controller = value
    end

    # Strings ("owner/name") or Hashes: { name:, changelog: true, gem: nil }. `changelog: false` keeps a repository
    # on the roadmap but never drafts changelog entries from its pull requests or commits. `gem:` is the gem's
    # name in the host's lockfile.
    def repositories=(value)
      normalize_repositories(value)
      @repositories = value
    end

    def initialize
      @repositories = []
      @lockfile_path = "Gemfile.lock"
      @public_label = "public"
      @soon_labels = %w[soon]
      @excluded_labels = %w[internal dependencies refactor chore]
      @excluded_authors = [ /\[bot\]\z/ ]
      @commit_types = %w[feat fix perf]
      @tone = "Friendly, concise, no jargon. Address the customer as 'you'."
      @public_parent_controller = "ActionController::Base"
      @public_layout = "shiplog/application"
      @admin_parent_controller = "ActionController::Base"
      @admin_layout = "shiplog/admin"
      @classes = {}.freeze
      @stylesheet = true
      @admin_chrome = :standalone
      @admin_flash = true
      @authorize_admin = ->(_controller) { false }
      @current_admin = ->(controller) { controller.try(:current_user)&.try(:email) }
      @roadmap_path = "roadmap"
      @changelog_path = "changelog"
    end

    def resolved_github_token
      github_token.respond_to?(:call) ? github_token.call : github_token
    end

    # The configured spelling of a repository name (matched case-insensitively), or nil.
    def repository_configured?(name)
      return if name.blank?
      repository_names.find { |configured| configured.casecmp?(name.to_s) }
    end

    # Normalised options of every configured repository: [{ name:, changelog:, gem: }].
    def repository_entries = normalize_repositories(repositories)

    def repository_names = repository_entries.map { |entry| entry[:name] }

    def repository_options(name)
      return if name.blank?
      repository_entries.find { |entry| entry[:name].casecmp?(name.to_s) }
    end

    # False for roadmap-only repositories. Unknown repositories count as changelog sources.
    def changelog_repository?(name)
      repository_options(name)&.fetch(:changelog) != false
    end

    # { "gem name in the lockfile" => "owner/name" } for repositories with `gem:`.
    def tracked_gems
      repository_entries.select { |entry| entry[:gem] }.to_h { |entry| [ entry[:gem], entry[:name] ] }
    end

    def excluded_author?(login)
      excluded_authors.any? { |pattern| pattern === login }
    end

    private

    def normalize_repositories(value)
      raise ArgumentError, "config.repositories must be an Array, got #{value.inspect}" unless value.is_a?(Array)

      value.map { |item| normalize_repository(item) }
    end

    def normalize_repository(item)
      return { name: item, changelog: true, gem: nil } if item.is_a?(String) && item.present?
      raise ArgumentError, "Invalid repository #{item.inspect}: expected \"owner/name\" or a Hash" unless item.is_a?(Hash)

      options = item.transform_keys { |key| key.to_s.to_sym }
      unknown = options.keys - REPOSITORY_OPTION_KEYS
      raise ArgumentError, "Unknown repository option(s) #{unknown.map(&:inspect).join(", ")}. Valid: #{REPOSITORY_OPTION_KEYS.map(&:inspect).join(", ")}" if unknown.any?

      name, changelog, gem = options.values_at(:name, :changelog, :gem)
      changelog = true if changelog.nil?
      raise ArgumentError, "Repository #{item.inspect} needs a :name (\"owner/name\")" unless name.is_a?(String) && name.present?
      raise ArgumentError, "Repository #{name}: changelog must be true or false" unless [ true, false ].include?(changelog)
      raise ArgumentError, "Repository #{name}: gem must be a non-empty String" unless gem.nil? || (gem.is_a?(String) && gem.present?)

      { name:, changelog:, gem: }
    end

    def ensure_controller_not_loaded!(setting, namespace, name)
      return unless namespace.const_defined?(name, false) && !namespace.autoload?(name)

      raise ArgumentError, "config.#{setting} was set after #{namespace}::#{name} loaded, so it would have no effect. " \
        "Set it in config/initializers (before Shiplog controllers load)."
    end
  end
end
