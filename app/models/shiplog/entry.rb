module Shiplog
  class Entry < ApplicationRecord
    class InvalidTransition < StandardError; end

    belongs_to :subject, polymorphic: true
    belongs_to :area, class_name: "Shiplog::Area", optional: true

    enum :kind, %w[roadmap feature change].index_by(&:itself), validate: true
    enum :status, %w[draft approved discarded].index_by(&:itself), default: "draft", validate: true

    CHANGELOG_KINDS = %w[feature change].freeze

    validates :released_on, presence: true, if: -> { approved? && !roadmap? }
    validate :area_exists
    validate :kind_change_allowed, on: :update
    validate :kind_free_for_subject, on: :update

    SEARCH_MAX_LENGTH = 100
    SEARCH_MAX_WORDS = 5

    # The words of a search query: whitespace squished, cut at 100 characters, at most 5 words.
    def self.search_terms(query)
      query.to_s.squish.first(SEARCH_MAX_LENGTH).split.first(SEARCH_MAX_WORDS)
    end

    # Entries whose title or body contains every word of the query (case-insensitive, LIKE wildcards escaped).
    # A blank query leaves the scope unchanged.
    def self.search(query)
      search_terms(query).reduce(all) do |scope, term|
        pattern = "%#{sanitize_sql_like(term)}%"
        scope.where("#{table_name}.title ILIKE :pattern OR #{table_name}.body ILIKE :pattern", pattern:)
      end
    end

    UNSEEN_COUNT_CAP = 99
    SLUG_MAX_LENGTH = 80
    SLUG_ATTEMPTS = 5
    # What a slug may look like (the permalink route's constraint, /[a-z0-9-]+/, is the unanchored twin).
    SLUG_FORMAT = /\A[a-z0-9-]+\z/

    # What the public changelog lists: approved features and changes with a release date.
    scope :published_changelog, -> { approved.where(kind: CHANGELOG_KINDS).where.not(released_on: nil) }
    # The changelog's order, newest first. A missing approved_at sorts first within its day, as PostgreSQL
    # sorts NULLs in a descending order (the neighbour queries rely on it).
    scope :newest_first, -> { order(released_on: :desc, approved_at: :desc, id: :desc) }

    # The number of approved features and changes approved after `since` (all of them while it is nil), capped
    # at 99. One COUNT over the (status, approved_at) index.
    def self.unseen_count(since: nil)
      scope = approved.where(kind: CHANGELOG_KINDS)
      scope = scope.where("#{table_name}.approved_at > ?", since) if since
      scope.limit(UNSEEN_COUNT_CAP).count
    end

    # Gives every published changelog entry that has no slug one (oldest first, so the oldest keeps the plain
    # slug on duplicate titles). Returns how many it filled.
    def self.backfill_slugs
      published_changelog.where(slug: nil).order(:released_on, :approved_at, :id).to_a.count { |entry| entry.ensure_slug!.present? }
    end

    # Whether the entry has a slug the permalink route accepts. Entries without one (approved by older code) or
    # with a stray one render without a link rather than raising.
    def permalink?
      slug.is_a?(String) && SLUG_FORMAT.match?(slug)
    end

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
      retrying_on_slug_conflict do
        update!(status: "approved", approved_at: Time.current, approved_by: by, discard_reason: nil,
          released_on: released_on || Date.current, slug: slug_in_database || (generate_slug if permalinked?))
      end
    end

    # The slug of a published changelog entry, generated and stored when it has none (entries approved before
    # 0.3.0). Nil for entries without a permalink: drafts, discarded and roadmap entries.
    def ensure_slug!
      return slug if slug.present?
      return unless approved? && permalinked?

      retrying_on_slug_conflict { update_columns(slug: generate_slug) }
      slug
    end

    # The entries right after and before this one in the changelog's order, among the published ones.
    def newer_changelog_entry = changelog_neighbour(">", :asc)

    def older_changelog_entry = changelog_neighbour("<", :desc)

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

    def permalinked? = CHANGELOG_KINDS.include?(kind)

    # The title parameterized and cut at 80 characters, made unique with -2, -3, ...; entry-<id> when the title
    # has nothing left. The uniqueness check can lose a race, which the unique index catches (see
    # retrying_on_slug_conflict).
    def generate_slug
      base = dashed_title.first(SLUG_MAX_LENGTH).gsub(/\A-+|-+\z/, "").presence || "entry-#{id}"
      candidate = base
      suffix = 2
      while self.class.where(slug: candidate).where.not(id:).exists?
        tail = "-#{suffix}"
        candidate = "#{base.first(SLUG_MAX_LENGTH - tail.length).delete_suffix("-")}#{tail}"
        suffix += 1
      end
      candidate
    end

    # The title as [a-z0-9-] only: parameterized (which keeps underscores), underscores turned into dashes,
    # repeated dashes squeezed, dashes at both ends stripped.
    def dashed_title
      title.to_s.parameterize.tr("_", "-").squeeze("-").gsub(/\A-+|-+\z/, "")
    end

    # Runs the block in a savepoint (a unique violation aborts the surrounding PostgreSQL transaction otherwise)
    # and runs it again, with a fresh slug, when another entry took the slug first.
    def retrying_on_slug_conflict
      attempts = 0
      begin
        self.class.transaction(requires_new: true) { yield }
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        retry if attempts < SLUG_ATTEMPTS
        raise
      end
    end

    # The published entry next to this one: `operator` compares the (released_on, approved_at, id) keys of
    # the changelog order, with a missing approved_at as the largest value, as the descending order puts it.
    def changelog_neighbour(operator, direction)
      key = "(released_on, COALESCE(approved_at, 'infinity'::timestamp), id)"
      self.class.published_changelog
        .where("#{key} #{operator} (SELECT released_on, COALESCE(approved_at, 'infinity'::timestamp), id FROM #{self.class.table_name} WHERE id = ?)", id)
        .reorder(released_on: direction, approved_at: direction, id: direction).first
    end

    def kind_free_for_subject
      return unless will_save_change_to_kind? && self.class.where(subject_type:, subject_id:, kind:).where.not(id:).exists?

      errors.add(:changelog_kind, :taken)
    end

    def area_exists
      errors.add(:area, :invalid) if area_id && will_save_change_to_area_id? && area.nil?
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
