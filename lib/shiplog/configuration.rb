module Shiplog
  class Configuration
    attr_accessor :github_token, :webhook_secret,
      :public_label, :soon_labels, :excluded_labels, :excluded_authors, :commit_types,
      :rewriter, :product_name, :audience, :tone, :prompt_builder,
      :public_layout, :admin_layout,
      :stylesheet, :admin_flash, :authorize_admin, :current_admin,
      :roadmap_path

    ADMIN_CHROMES = %i[standalone hosted].freeze
    # Segments of only dots ("." and "..") are path traversal, not names.
    REPOSITORY_NAME = %r{\A(?!\.+/)[\w.-]+/(?!\.+\z)[\w.-]+\z}
    REPOSITORY_OPTION_KEYS = %i[name changelog gem].freeze

    attr_reader :repositories
    # Path of the lockfile read in merged pull requests to detect gem upgrades (see config.repositories `gem:`).
    attr_accessor :lockfile_path

    # The public changelog's path: segments of a-z, 0-9, dashes and underscores, joined by slashes ("changelog",
    # "docs/whats_new"); surrounding slashes are stripped. Permalinks live below it and the Atom feed is
    # "<path>.atom". Read when routes are drawn.
    attr_reader :changelog_path
    CHANGELOG_PATH = %r{\A[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*\z}

    # The site's canonical origin, e.g. "https://trackberry.com" (nil by default). When set, the Atom feed's ids
    # and links, entry links, og:url and the other absolute URLs use it instead of the request's host, which
    # varies (apex and www, a forged X-Forwarded-Host). An origin only: scheme, host and optional port. Any path
    # prefix of the engine's mount comes from the routes, so it needs no place here.
    attr_reader :canonical_url

    attr_reader :admin_chrome, :classes, :public_parent_controller, :admin_parent_controller

    # Product updates navigation and roadmap options.
    attr_accessor :feedback_path
    # Whether the public changelog has a search box and honours ?q= (default true).
    attr_accessor :changelog_search
    # Called with the controller on each changelog index or permalink view (200 or 304 answers), e.g. to stamp
    # the visitor's "last seen" time. It runs BEFORE the page renders (so a badge in the same response is
    # current), on every visit, and may write: keep it cheap, e.g. write only when the stored time is older than
    # the newest entry. Nil by default. Not part of the ETag: it doesn't change the markup.
    attr_reader :on_changelog_seen
    # Bump it when the output of a callable you configured changes (extra_pages, repository_labels, feedback_path):
    # callables cannot be part of the ETag, so this is how cached public pages learn about it.
    attr_accessor :cache_version
    attr_reader :extra_pages, :repository_labels, :roadmap_shipped_count
    # How many product areas the AI may create (default 8). Past it, entries can only join existing areas.
    # Not part of render_digest: the markup depends on the areas themselves, which the ETag carries.
    attr_reader :max_areas

    EXTRA_PAGE_KEYS = %i[label path].freeze

    # A path (not "//host", "/\host" or "/ x", which browsers read as other targets), an http(s) URL or mailto:.
    SAFE_URL = %r{\A(?:/(?![/\\\s])|https?://|mailto:)}i

    # Whether a link target is safe to render: a path, an http(s) URL or a mailto: address.
    def self.safe_url?(value)
      value.is_a?(String) && SAFE_URL.match?(value.strip) && !value.match?(/[[:cntrl:]]/)
    end

    # A digest of everything configured that changes the public markup, stable across processes and servers
    # (no Object#hash). Callables are represented by a marker; see cache_version.
    def render_digest
      stable = ->(value) { value.respond_to?(:call) ? "callable" : value }
      data = [
        classes.sort_by { |key, _| key.to_s }.map { |key, value| [ key.to_s, Array(value).map(&:to_s) ] },
        stylesheet, roadmap_shipped_count, cache_version, product_name, canonical_url,
        extra_pages.map { |page| [ stable.(page[:label]), stable.(page[:path]) ] },
        repository_labels.sort_by { |name, _| name.to_s }.map { |name, label| [ name, stable.(label) ] },
        stable.(feedback_path), changelog_search
      ]
      Digest::SHA256.hexdigest(JSON.generate(data))
    end

    # Pages added to the switcher after Roadmap and Changelog: [{ label:, path: }]. Each is a String, or a callable
    # evaluated in the view (instance_exec), e.g. `path: -> { main_app.news_path }`.
    def extra_pages=(value)
      raise ArgumentError, "extra_pages must be an Array of { label:, path: } Hashes, got #{value.inspect}" unless value.nil? || value.is_a?(Array)
      pages = (value || []).map do |page|
        raise ArgumentError, "Each extra page must be a Hash with :label and :path, got #{page.inspect}" unless page.is_a?(Hash)
        page = page.to_h.transform_keys { |key| key.to_s.to_sym }
        unless page.keys.sort == EXTRA_PAGE_KEYS
          raise ArgumentError, "An extra page needs exactly the keys :label and :path, got #{page.keys.inspect}"
        end
        page.each do |key, item|
          valid = item.respond_to?(:call) || (item.is_a?(String) && item.present?)
          raise ArgumentError, "Extra page #{key} must be a non-empty String or a callable, got #{item.inspect}" unless valid
          if key == :path && item.is_a?(String) && !self.class.safe_url?(item)
            raise ArgumentError, "Extra page path must be relative (/...), http(s):// or mailto:, got #{item.inspect}"
          end
        end
        { label: page[:label], path: page[:path] }.freeze
      end
      @extra_pages = pages.freeze
    end

    # Display names for repositories on roadmap cards: { "owner/name" => "iPhone & iPad" }. Values are Strings or
    # callables evaluated in the view.
    def repository_labels=(value)
      labels = value.nil? ? {} : value
      raise ArgumentError, "repository_labels must be a Hash, got #{value.inspect}" unless labels.is_a?(Hash)
      labels.each do |name, label|
        unless label.respond_to?(:call) || label.is_a?(String)
          raise ArgumentError, "repository_labels[#{name.inspect}] must be a String or a callable, got #{label.inspect}"
        end
      end
      @repository_labels = labels.transform_keys(&:to_s).freeze
    end

    # How many recently shipped changelog entries the roadmap lists; 0 hides the section.
    def roadmap_shipped_count=(value)
      raise ArgumentError, "roadmap_shipped_count must be a non-negative Integer, got #{value.inspect}" unless value.is_a?(Integer) && value >= 0
      @roadmap_shipped_count = value
    end

    def max_areas=(value)
      raise ArgumentError, "max_areas must be a non-negative Integer, got #{value.inspect}" unless value.is_a?(Integer) && value >= 0
      @max_areas = value
    end

    def changelog_path=(value)
      path = value.gsub(%r{\A/+|/+\z}, "") if value.is_a?(String)
      unless path && CHANGELOG_PATH.match?(path)
        raise ArgumentError, "changelog_path must be a path of letters, digits, dashes and underscores, with / between segments (like \"changelog\"), got #{value.inspect}"
      end
      @changelog_path = path
    end

    def canonical_url=(value)
      @canonical_url = normalize_canonical_url(value)
    end

    def on_changelog_seen=(value)
      raise ArgumentError, "on_changelog_seen must be nil or a callable, got #{value.inspect}" unless value.nil? || value.respond_to?(:call)
      @on_changelog_seen = value
    end

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
      warn_double_drafting(normalize_repositories(value))
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
      @extra_pages = [].freeze
      @repository_labels = {}.freeze
      @roadmap_shipped_count = 4
      @changelog_search = true
      @max_areas = 8
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

    def normalize_canonical_url(value)
      return if value.nil? || (value.is_a?(String) && value.strip.empty?)
      raise ArgumentError, "canonical_url must be a String like \"https://example.com\", got #{value.inspect}" unless value.is_a?(String)

      uri = begin
        URI.parse(value.strip)
      rescue URI::InvalidURIError
        nil
      end
      valid = uri.is_a?(URI::HTTP) && uri.host.present? && [ "", "/" ].include?(uri.path) && uri.query.nil? && uri.fragment.nil? && uri.userinfo.nil?
      raise ArgumentError, "canonical_url must be an http(s) origin without path, query or credentials (\"https://example.com\"), got #{value.inspect}" unless valid

      port = ":#{uri.port}" unless uri.port == uri.default_port
      "#{uri.scheme}://#{uri.host.downcase}#{port}"
    end

    def normalize_repositories(value)
      raise ArgumentError, "config.repositories must be an Array, got #{value.inspect}" unless value.is_a?(Array)

      value.map { |item| normalize_repository(item) }
    end

    # A gem repository that also drafts its own changelog entries announces each change twice: once from its own
    # pull requests and once from the host's upgrade pull request.
    def warn_double_drafting(entries)
      entries.select { |entry| entry[:gem] && entry[:changelog] }.each do |entry|
        Rails.logger&.warn("[shiplog] Repository #{entry[:name]} has gem: #{entry[:gem].inspect} and changelog: true, so its changes " \
          "are drafted twice (from its own pull requests and from the host's upgrade pull request). Set changelog: false.")
      end
    end

    def normalize_repository(item)
      return { name: valid_repository_name!(item), changelog: true, gem: nil } if item.is_a?(String) && item.present?
      raise ArgumentError, "Invalid repository #{item.inspect}: expected \"owner/name\" or a Hash" unless item.is_a?(Hash)

      options = item.transform_keys { |key| key.to_s.to_sym }
      unknown = options.keys - REPOSITORY_OPTION_KEYS
      raise ArgumentError, "Unknown repository option(s) #{unknown.map(&:inspect).join(", ")}. Valid: #{REPOSITORY_OPTION_KEYS.map(&:inspect).join(", ")}" if unknown.any?

      name, changelog, gem = options.values_at(:name, :changelog, :gem)
      changelog = true if changelog.nil?
      raise ArgumentError, "Repository #{item.inspect} needs a :name (\"owner/name\")" unless name.is_a?(String) && name.present?
      valid_repository_name!(name)
      raise ArgumentError, "Repository #{name}: changelog must be true or false" unless [ true, false ].include?(changelog)
      raise ArgumentError, "Repository #{name}: gem must be a non-empty String" unless gem.nil? || (gem.is_a?(String) && gem.present?)

      { name:, changelog:, gem: }
    end

    def valid_repository_name!(name)
      raise ArgumentError, "Invalid repository name #{name.inspect}: expected \"owner/name\"" unless REPOSITORY_NAME.match?(name)

      name
    end

    def ensure_controller_not_loaded!(setting, namespace, name)
      return unless namespace.const_defined?(name, false) && !namespace.autoload?(name)

      raise ArgumentError, "config.#{setting} was set after #{namespace}::#{name} loaded, so it would have no effect. " \
        "Set it in config/initializers (before Shiplog controllers load)."
    end
  end
end
