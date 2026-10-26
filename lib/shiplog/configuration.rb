module Shiplog
  class Configuration
    attr_accessor :repositories, :github_token, :webhook_secret,
      :public_label, :soon_labels, :excluded_labels, :excluded_authors, :commit_types,
      :rewriter, :product_name, :audience, :tone, :prompt_builder,
      :public_parent_controller, :public_layout, :authorize_admin, :current_admin,
      :roadmap_path, :changelog_path

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
      @authorize_admin = ->(_controller) { true }
      @current_admin = ->(controller) { controller.try(:current_user)&.try(:email) }
      @roadmap_path = "roadmap"
      @changelog_path = "changelog"
    end

    def resolved_github_token
      github_token.respond_to?(:call) ? github_token.call : github_token
    end

    def excluded_author?(login)
      excluded_authors.any? { |pattern| pattern === login }
    end
  end
end
