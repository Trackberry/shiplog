module Shiplog
  # Backfills product areas for entries that have none (see AreaDetector). Enqueued by the admin's Areas page.
  class DetectAreasJob < ApplicationJob
    def perform
      AreaDetector.new.call
    end
  end
end
