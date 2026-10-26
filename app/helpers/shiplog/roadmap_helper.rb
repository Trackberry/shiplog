module Shiplog
  module RoadmapHelper
    include Shiplog::SwitcherHelper

    # English texts of the roadmap columns, used when the host's locale has no shiplog.columns translations.
    COLUMN_DEFAULTS = {
      in_progress: { title: "In progress", description: "What we're building now" },
      coming_soon: { title: "Coming soon", description: "Planned next" },
      later: { title: "Later", description: "On our radar" }
    }.freeze

    def shiplog_column_defaults = COLUMN_DEFAULTS

    # The configured label of a repository (config.repository_labels, matched case-insensitively), or nil.
    def shiplog_repository_label(repository)
      labels = Shiplog.config.repository_labels
      label = labels[repository.full_name] || labels.find { |name, _| name.casecmp?(repository.full_name) }&.last
      shiplog_resolve(label).presence
    end

    # The "suggest a feature" target (String or callable), or nil.
    def shiplog_feedback_path = shiplog_safe_url(shiplog_resolve(Shiplog.config.feedback_path))
  end
end
