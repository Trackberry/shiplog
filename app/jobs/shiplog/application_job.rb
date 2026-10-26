module Shiplog
  class ApplicationJob < ActiveJob::Base
    MAX_RATE_LIMIT_RETRIES = 5

    rescue_from Github::RateLimited do |error|
      if executions >= MAX_RATE_LIMIT_RETRIES
        Rails.error.report(error, handled: false, context: { job: self.class.name, executions: })
        raise error
      end

      retry_job wait_until: error.reset_at + 1.second
    end
  end
end
