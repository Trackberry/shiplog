module Shiplog
  class Entry < ApplicationRecord
    class InvalidTransition < StandardError; end

    include Images

    belongs_to :subject, polymorphic: true
    belongs_to :area, class_name: "Shiplog::Area", optional: true
    has_many :translations, class_name: "Shiplog::EntryTranslation", dependent: :destroy, inverse_of: :entry

    enum :kind, %w[roadmap feature change announcement].index_by(&:itself), validate: true
    enum :status, %w[draft approved discarded].index_by(&:itself), default: "draft", validate: true

    CHANGELOG_KINDS = %w[feature change].freeze
    # The slug of a month's announcement ("2026-10"). Features and changes never get one of this shape, so an
    # announcement's page URL is known before it is drafted.
    ANNOUNCEMENT_SLUG = /\A\d{4}-\d{2}\z/

    validates :released_on, presence: true, if: -> { approved? && !roadmap? }
    validate :area_exists
    validate :kind_change_allowed, on: :update
    validate :kind_free_for_subject, on: :update

    # An announcement that leaves "approved" may be announced again once it is approved again.
    before_save :clear_announced_at, if: -> { announcement? && will_save_change_to_status? && !approved? }

    # Approving an entry, or changing the English text of an approved one, translates it into every configured
    # locale (see TranslateEntryJob). After the commit, so the job reads what was saved.
    after_commit :enqueue_translations, on: :update, if: :translation_due?
    # Approving an announcement calls config.on_announcement_approved once its translations are current (see
    # AnnounceJob, which TranslateEntryJob enqueues too).
    after_commit :enqueue_announcement, on: :update, if: -> { announcement? && approved? && saved_change_to_status? }

    SEARCH_MAX_LENGTH = 100
    SEARCH_MAX_WORDS = 5

    # The words of a search query: whitespace squished, cut at 100 characters, at most 5 words.
    def self.search_terms(query)
      query.to_s.squish.first(SEARCH_MAX_LENGTH).split.first(SEARCH_MAX_WORDS)
    end

    # Entries whose title or body contains every word of the query (case-insensitive, LIKE wildcards escaped).
    # With a configured `locale` other than the default, a word also matches the current translation of that
    # locale (the text the page shows), not a stale one. A blank query leaves the scope unchanged.
    def self.search(query, locale: nil)
      locale = locale.to_s.presence_in(Shiplog.config.locales.map(&:to_s))
      search_terms(query).reduce(all) do |scope, term|
        pattern = "%#{sanitize_sql_like(term)}%"
        english = "#{table_name}.title ILIKE :pattern OR #{table_name}.body ILIKE :pattern"
        next scope.where(english, pattern:) unless locale

        # One fragment, so the user's value is bound exactly once: the named binds are substituted in a single
        # pass and the quoted text is never scanned again. Everything else in it is a constant.
        translations = EntryTranslation.table_name
        translated = "EXISTS (SELECT 1 FROM #{translations} WHERE #{translations}.entry_id = #{table_name}.id " \
          "AND #{translations}.locale = :locale AND #{translations}.source_digest = #{TRANSLATION_DIGEST_SQL} " \
          "AND (#{translations}.title ILIKE :pattern OR #{translations}.body ILIKE :pattern))"
        scope.where("#{english} OR #{translated}", pattern:, locale:)
      end
    end

    # Loads the translations of `entries` for the current locale in one query, and none under a locale that is
    # not translated (then the entries show English and nothing is queried). Only that locale's rows are loaded
    # into the `translations` association, so after this call it holds the current locale's rows, not all of them
    # (use Entry#translation, not `translations`, to read them).
    def self.preload_translations(entries, locale: I18n.locale)
      entries = Array(entries).compact
      return unless entries.any? && translated_locale?(locale)

      ActiveRecord::Associations::Preloader.new(records: entries, associations: :translations,
        scope: EntryTranslation.where(locale: locale.to_s)).call
    end

    # Whether pages in this locale show translations: it is one of config.locales.
    def self.translated_locale?(locale) = Shiplog.config.locales.any? { |configured| configured.to_s == locale.to_s }

    # The SQL twin of #translation_source_digest: SHA-256 of "title\nbody" (a missing text is empty), in hex.
    TRANSLATION_DIGEST_SQL = "encode(sha256(convert_to(COALESCE(#{table_name}.title, '') || E'\\n' || COALESCE(#{table_name}.body, ''), 'UTF8')), 'hex')".freeze

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
    # at 99. One COUNT over the (status, approved_at) index. It filters on approved_at, not on released_on (the
    # list's order): "new since you last looked" is about when an entry appeared, so an entry approved today
    # with an earlier release date still counts as new.
    def self.unseen_count(since: nil) = count_approved_since(CHANGELOG_KINDS, since)

    # The number of approved announcements approved after `since` (all of them while it is nil), capped at 99.
    def self.unseen_announcements_count(since: nil) = count_approved_since("announcement", since)

    def self.count_approved_since(kinds, since)
      scope = approved.where(kind: kinds)
      scope = scope.where("#{table_name}.approved_at > ?", since) if since
      scope.limit(UNSEEN_COUNT_CAP).count
    end
    private_class_method :count_approved_since

    # Approved announcements: the ones with a public page (config.announcements = :page) or a host link.
    scope :published_announcements, -> { approved.where(kind: "announcement").where.not(released_on: nil) }

    # Gives every published changelog entry that has no slug one (oldest first, so the oldest keeps the plain
    # slug on duplicate titles). Returns how many it filled.
    def self.backfill_slugs
      published_changelog.where(slug: nil).order(:released_on, :approved_at, :id).to_a.count { |entry| entry.ensure_slug!.present? }
    end

    # Approved entries with no current translation into `locale`: none at all, or one made from older English text
    # (compared with the SQL twin of the digest, in one query).
    def self.missing_translation(locale)
      translations = EntryTranslation.table_name
      current = EntryTranslation.where(locale: locale.to_s).where("#{translations}.entry_id = #{table_name}.id")
        .where("#{translations}.source_digest = #{TRANSLATION_DIGEST_SQL}")
      approved.where(current.arel.exists.not)
    end

    # Enqueues a TranslateEntryJob for every approved entry and configured locale that has no current translation,
    # reading the entries in batches. Repeating it is harmless: the job itself skips a translation that is current.
    # Returns { approved: how many approved entries, enqueued: { locale => how many jobs } }.
    def self.enqueue_missing_translations(batch_size: 100)
      enqueued = Shiplog.config.locales.index_with do |locale|
        count = 0
        missing_translation(locale).find_each(batch_size:) do |entry|
          TranslateEntryJob.perform_later(entry, locale.to_s)
          count += 1
        end
        count
      end
      { approved: approved.count, enqueued: }
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

    # The digest of what a draft was written from: the GitHub title and body, or for an announcement the month's
    # entries (Period#content_digest). A draft whose stored digest differs is flagged in the admin.
    def self.digest_for(subject)
      return subject.content_digest if subject.is_a?(Period)

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
    # 0.3.0). Nil for entries without a permalink: drafts, discarded and roadmap entries. The write only happens
    # while the slug is still null in the database, so a concurrent writer's slug is never overwritten; the
    # entry is reloaded to return whichever slug won. Not used by the public pages (they must not write, a GET
    # may hit a read replica): approve! and `rake shiplog:backfill_slugs` create slugs.
    def ensure_slug!
      return slug if slug.present?
      return unless approved? && permalinked?

      retrying_on_slug_conflict { self.class.where(id:, slug: nil).update_all(slug: generate_slug, updated_at: Time.current) }
      reload.slug
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

    # The digest of the English title and body, stored in a translation made from them. A translation whose digest
    # differs from it is stale.
    def translation_source_digest
      Digest::SHA256.hexdigest([ title, body ].join("\n"))
    end

    # The current translation for a locale (the request's by default): nil under a locale that is not configured,
    # when none exists, and when it is stale. Reads the preloaded translations (see Entry.preload_translations)
    # and asks the database only when they were not loaded.
    def translation(locale = I18n.locale)
      return unless self.class.translated_locale?(locale)

      found = translations.loaded? ? translations.find { |record| record.locale == locale.to_s } : translations.find_by(locale: locale.to_s)
      found if found && found.source_digest == translation_source_digest
    end

    # What public pages show: the translation for the request's locale when there is a current one, else English.
    def display_title(locale = I18n.locale) = translation(locale)&.title || title

    # The translated body, or the English one when the translation's body is blank and the English one is not
    # (a blank body is never published in place of text).
    def display_body(locale = I18n.locale)
      translated = translation(locale)&.body
      translated.blank? && body.present? ? body : (translated || body)
    end

    # Whether every configured locale has a current translation (always true without config.locales).
    def translations_current? = Shiplog.config.locales.all? { |locale| translation(locale) }

    # The title, Markdown body, HTML and plain text of an announcement in a locale (the default one when omitted):
    # the current translation when there is one, else the English text. For config.on_announcement_approved and the
    # admin's export.
    def to_markdown(locale = I18n.default_locale) = display_body(locale).to_s
    def to_html(locale = I18n.default_locale) = Markdown.to_html(display_body(locale))
    def to_text(locale = I18n.default_locale) = Markdown.to_text(display_body(locale))

    # The absolute URL of the entry's public page (see PublicLinks), or nil without a slug. For an announcement
    # with config.announcements = :external, the host's own page is elsewhere (config.announcement_url).
    def public_url = PublicLinks.entry_url(self)

    # Whether the translations an announcement waits for are there: all current, or none can be made because there
    # is no rewriter (then hosts get the English text, or an admin's hand-made translations).
    def translations_ready? = Shiplog.config.rewriter.nil? || translations_current?

    # Runs the block (the host's hook, see AnnounceJob) once for this approval, when this is an approved announcement
    # not announced yet whose translations are ready (`force: true` skips that last check: the admin's "Notify
    # now"). The block runs under the row lock and announced_at is stored in the same transaction, so two jobs
    # never both run it, and a block that raises (or a worker that dies) stores nothing and is run again by the
    # retry. Returns whether the block ran.
    def announce!(force: false)
      with_lock do
        reload
        next false unless announcement? && approved? && announced_at.nil? && (force || translations_ready?)

        yield
        update_columns(announced_at: Time.current)
        true
      end
    end

    def source_changed?
      source_digest.present? && source_digest != self.class.digest_for(subject)
    end

    private

    def translation_due?
      approved? && Shiplog.config.locales.any? && (saved_change_to_status? || saved_change_to_title? || saved_change_to_body?)
    end

    def enqueue_translations
      Shiplog.config.locales.each { |locale| TranslateEntryJob.perform_later(self, locale) }
    end

    # Features and changes get a slug when approved; an announcement gets its month's slug when drafted.
    def permalinked? = CHANGELOG_KINDS.include?(kind)

    # Written whatever this instance holds: AnnounceJob sets the column with update_columns, so an instance loaded
    # before it may still hold nil and would otherwise see no change to save.
    def clear_announced_at
      self.announced_at = nil
      attribute_will_change!("announced_at")
    end

    def enqueue_announcement
      AnnounceJob.perform_later(self)
    end

    # The title parameterized and cut at 80 characters, made unique with -2, -3, ...; entry-<id> when the title
    # has nothing left. A month's shape ("2026-10") is kept for announcements and gets a suffix too. The
    # uniqueness check can lose a race, which the unique index catches (see retrying_on_slug_conflict).
    def generate_slug
      base = dashed_title.first(SLUG_MAX_LENGTH).gsub(/\A-+|-+\z/, "").presence || "entry-#{id}"
      candidate = base
      suffix = 2
      while ANNOUNCEMENT_SLUG.match?(candidate) || self.class.where(slug: candidate).where.not(id:).exists?
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
