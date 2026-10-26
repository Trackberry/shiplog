module Shiplog
  # Backfills product areas for entries that have none (see AreaDetector). Enqueued by the admin's Areas page.
  class DetectAreasJob < ApplicationJob
    # recheck: true first makes the entries the AI left unplaced eligible again.
    def perform(recheck: false)
      AreaDetector.new.call(recheck:)
    end
  end
end
