module Shiplog
  module RoadmapHelper
    include Shiplog::SwitcherHelper

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
