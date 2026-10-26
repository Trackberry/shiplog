module Shiplog
  class Configuration
    attr_accessor :repositories, :github_token, :webhook_secret,
      :public_label, :soon_labels, :excluded_labels, :excluded_authors, :commit_types,
      :rewriter, :product_name, :audience, :tone, :prompt_builder,
      :public_parent_controller, :public_layout, :admin_parent_controller, :admin_layout,
      :classes, :stylesheet, :admin_flash, :authorize_admin, :current_admin,
      :roadmap_path, :changelog_path

    ADMIN_CHROMES = %i[standalone hosted].freeze

    attr_reader :admin_chrome

    # :standalone (default) wraps the admin in Shiplog's own page chrome; :hosted renders it inside the
    # layout of config.admin_layout (compact sub-nav, no page chrome of its own).
    def admin_chrome=(value)
      chrome = value.to_s.to_sym if value.respond_to?(:to_sym)
      unless ADMIN_CHROMES.include?(chrome)
        raise ArgumentError, "Invalid admin_chrome #{value.inspect}. Valid values: #{ADMIN_CHROMES.map(&:inspect).join(", ")}"
      end
      @admin_chrome = chrome
    end

    def initialize
      @repositories = []
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
      @classes = {}
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
      repositories.find { |configured| configured.casecmp?(name.to_s) }
    end

    def excluded_author?(login)
      excluded_authors.any? { |pattern| pattern === login }
    end
  end
end
