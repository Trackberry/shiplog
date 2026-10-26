module Shiplog
  class Rewriter
    class Prompt
      KIND_LABELS = { "roadmap" => "upcoming feature", "feature" => "shipped feature", "change" => "small change" }.freeze

      TEMPLATE = <<~PROMPT.freeze
        You write release notes for %<product_name>s, used by %<audience>s.
        Tone: %<tone>s
        Rewrite the following %<kind_label>s for customers who are not developers.
        Explain what changes for them, not how it was built. Never mention code, tables, refactors, gems, or internal names.
        Title: at most 8 words. Body: 1–3 short sentences (features may use up to 2 short paragraphs).
        Reply with JSON only: {"title": "...", "body": "...", "customer_facing": true|false}
        Set customer_facing to false if a customer would not notice this change.
        ---
        %<context>s
      PROMPT

      def initialize(entry)
        @entry = entry
        @subject = entry.subject
      end

      def to_s
        builder = Shiplog.config.prompt_builder
        return builder.call(kind: @entry.kind, context: context) if builder

        config = Shiplog.config
        format(TEMPLATE, product_name: config.product_name, audience: config.audience, tone: config.tone,
          kind_label: KIND_LABELS.fetch(@entry.kind), context: render_context)
      end

      private
        def context
          @context ||= { title: @subject.title, body: @subject.body.to_s }.tap do |data|
            next unless @entry.feature?

            data[:sections] = IssueForm.parse(@subject.body).compact
            data[:child_issues] = children.map(&:title)
            data[:pull_requests] = linked_pull_requests.map(&:title)
          end
        end

        def render_context
          lines = [ "Title: #{context[:title]}", "Description: #{context[:body]}" ]
          context[:sections]&.each { |name, text| lines << "#{name.humanize}: #{text}" }
          lines << "Sub-issues: #{context[:child_issues].join('; ')}" if context[:child_issues].present?
          lines << "Pull requests: #{context[:pull_requests].join('; ')}" if context[:pull_requests].present?
          lines.join("\n")
        end

        def children = @children ||= @subject.descendants

        def linked_pull_requests
          node_ids = [ @subject.node_id, *children.map(&:node_id) ]
          PullRequest.joins(:issue_links).where(issue_links: { issue_node_id: node_ids }).distinct.order(:number)
        end
    end
  end
end
