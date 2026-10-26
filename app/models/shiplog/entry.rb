module Shiplog
  class Entry < ApplicationRecord
    class InvalidTransition < StandardError; end

    belongs_to :subject, polymorphic: true

    enum :kind, %w[roadmap feature change].index_by(&:itself), validate: true
    enum :status, %w[draft approved discarded].index_by(&:itself), default: "draft", validate: true

    CHANGELOG_KINDS = %w[feature change].freeze

    validates :released_on, presence: true, if: -> { approved? && !roadmap? }
    validate :kind_change_allowed, on: :update
    validate :kind_free_for_subject, on: :update

    def changelog_kind = kind

    # Switches a changelog entry between "feature" and "change". Roadmap entries never convert, and
    # anything other than those two values is ignored.
    def changelog_kind=(value)
      self.kind = value if CHANGELOG_KINDS.include?(kind) && CHANGELOG_KINDS.include?(value)
    end

    def self.digest_for(subject)
      Digest::SHA256.hexdigest([ subject.title, subject.body ].join("\n"))
    end

    def approve!(by:)
      require_status!("approve", from: "draft")
      update!(status: "approved", approved_at: Time.current, approved_by: by, discard_reason: nil,
        released_on: released_on || Date.current)
    end

    def discard!(reason:)
      require_status!("discard", from: "draft")
      update!(status: "discarded", discard_reason: reason)
    end

    def restore!
      require_status!("restore", from: "discarded")
      update!(status: "draft", discard_reason: nil)
    end

    def source_changed?
      source_digest.present? && source_digest != self.class.digest_for(subject)
    end

    private

    def kind_free_for_subject
      return unless will_save_change_to_kind? && self.class.where(subject_type:, subject_id:, kind:).where.not(id:).exists?

      errors.add(:changelog_kind, :taken)
    end

    def kind_change_allowed
      return unless will_save_change_to_kind?

      errors.add(:kind, :invalid) unless CHANGELOG_KINDS.include?(kind_in_database) && CHANGELOG_KINDS.include?(kind)
    end

    def require_status!(action, from:)
      raise InvalidTransition, "Cannot #{action} an entry that is #{status}" unless status == from
    end
  end
end
