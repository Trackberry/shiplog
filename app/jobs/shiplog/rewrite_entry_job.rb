module Shiplog
  class RewriteEntryJob < ApplicationJob
    discard_on ActiveRecord::RecordNotFound

    # After writing the draft, screenshots from the GitHub body are attached to a draft that has none (the
    # fetcher checks, never raises, and leaves approved entries alone).
    def perform(entry_id, force: false)
      entry = Rewriter.new(Entry.find(entry_id)).call(force:)
      ImageFetcher.call(entry)
    end
  end
end
