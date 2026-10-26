module Shiplog
  class Entry < ApplicationRecord
    belongs_to :subject, polymorphic: true

    enum :kind, %w[roadmap feature change].index_by(&:itself), validate: true
    enum :status, %w[draft approved discarded].index_by(&:itself), default: "draft", validate: true

    def self.digest_for(subject)
      Digest::SHA256.hexdigest([ subject.title, subject.body ].join("\n"))
    end

    def approve!(by:)
      update!(status: "approved", approved_at: Time.current, approved_by: by, discard_reason: nil,
        released_on: released_on || Date.current)
    end

    def discard!(reason:)
      update!(status: "discarded", discard_reason: reason)
    end

    def restore!
      update!(status: "draft", discard_reason: nil)
    end

    def source_changed?
      source_digest.present? && source_digest != self.class.digest_for(subject)
    end
  end
end
