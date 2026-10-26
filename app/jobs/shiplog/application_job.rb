module Shiplog
  class ApplicationJob < ActiveJob::Base
    MAX_RATE_LIMIT_RETRIES = 5

    rescue_from Github::RateLimited do |error|
      raise error if executions >= MAX_RATE_LIMIT_RETRIES

      retry_job wait_until: error.reset_at + 1.second
    end
  end
end
