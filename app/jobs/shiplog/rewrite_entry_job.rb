module Shiplog
  class RewriteEntryJob < ApplicationJob
    discard_on ActiveRecord::RecordNotFound

    def perform(entry_id, force: false)
      Rewriter.new(Entry.find(entry_id)).call(force:)
    end
  end
end
