module Shiplog
  class WebhooksController < ActionController::Base
    MAX_BODY_BYTES = 25.megabytes

    skip_forgery_protection
    layout false

    before_action :disable_session
    before_action :reject_oversized_body
    before_action :require_secret
    before_action :verify_signature

    def create
      payload = parse_payload or return head(:bad_request)
      event = request.headers["X-GitHub-Event"].to_s
      return head(:ok) if event == "ping"

      delivery = record_delivery(event, payload) or return head(:accepted)
      enqueue_refreshes(delivery, event, payload)
    end

    private

    def disable_session
      request.session_options[:skip] = true
    end

    def reject_oversized_body
      return head :content_too_large if request.content_length.to_i > MAX_BODY_BYTES

      # Content-Length may be absent (chunked) or wrong; check what was actually received.
      head :content_too_large if request.raw_post.bytesize > MAX_BODY_BYTES
    end

    def require_secret
      head :service_unavailable if Shiplog.config.webhook_secret.blank?
    end

    def verify_signature
      signature = WebhookSignature.new(
        secret: Shiplog.config.webhook_secret.to_s,
        body: request.raw_post,
        header: request.headers["X-Hub-Signature-256"]
      )
      head :unauthorized unless signature.valid?
    end

    def parse_payload
      payload = JSON.parse(request.raw_post)
      payload if payload.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end

    # Returns the delivery to process: a new one, or an earlier one that failed (error, never processed).
    def record_delivery(event, payload)
      WebhookDelivery.create!(
        delivery_id: request.headers["X-GitHub-Delivery"].to_s,
        event: event,
        action: payload["action"],
        repository_full_name: payload.dig("repository", "full_name"),
        received_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      retry_failed_delivery
    end

    # Claims atomically (clearing the error) so concurrent redeliveries do not both reprocess.
    def retry_failed_delivery
      failed = WebhookDelivery.where(delivery_id: request.headers["X-GitHub-Delivery"].to_s, processed_at: nil).where.not(error: nil)
      delivery = failed.first
      delivery if delivery && failed.where(id: delivery.id).update_all(error: nil, updated_at: Time.current) == 1
    end

    def enqueue_refreshes(delivery, event, payload)
      refresh_targets(event, payload).each { |target| RefreshJob.perform_later(*target) }
      delivery.update!(processed_at: Time.current)
      head :accepted
    rescue => error
      delivery.update(error: "#{error.class}: #{error.message}")
      head :internal_server_error
    end

    def refresh_targets(event, payload)
      targets =
        case event
        when "issues" then [ [ payload.dig("repository", "full_name"), "issue", payload.dig("issue", "number") ] ]
        when "pull_request" then [ [ payload.dig("repository", "full_name"), "pull_request", payload.dig("pull_request", "number") ] ]
        when "sub_issues" then sub_issue_targets(payload)
        else []
        end
      targets.uniq.select { |repo, _, number| number && Shiplog.config.repositories.include?(repo) }
    end

    def sub_issue_targets(payload)
      here = payload.dig("repository", "full_name")
      if payload["action"].to_s.start_with?("parent_issue")
        [ [ here, "issue", payload.dig("sub_issue", "number") ],
          [ payload.dig("parent_issue_repo", "full_name"), "issue", payload.dig("parent_issue", "number") ] ]
      else
        [ [ here, "issue", payload.dig("parent_issue", "number") ],
          [ payload.dig("sub_issue_repo", "full_name"), "issue", payload.dig("sub_issue", "number") ] ]
      end
    end
  end
end
