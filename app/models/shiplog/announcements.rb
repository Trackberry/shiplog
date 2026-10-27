module Shiplog
  # Monthly announcements: a short, AI-drafted summary of what shipped in a month, approved by an admin like every
  # other entry (kind "announcement", subject a Shiplog::Period). Where it is published is config.announcements.
  module Announcements
    # The slug used when a feature or change approved before 0.4.0 already took the month's own ("2026-10").
    FALLBACK_SUFFIX = "-update".freeze

    # Drafts the announcement of the month containing `month` and enqueues its rewrite. Returns the new draft, or
    # nil when announcements are off, the month has no approved feature or change (nothing to announce), or it
    # has an announcement already (whatever its status).
    def self.draft(month:)
      return unless Shiplog.announcements?

      starts_on = month.to_date.beginning_of_month
      return unless Period.changelog_entries_between(starts_on..starts_on.end_of_month).exists?

      period = Period.month(starts_on)
      Drafter.draft(period, "announcement", released_on: period.ends_on, slug: slug_for(period))
    end

    # The months an admin can draft from the admin: the current one (so far) and the previous one.
    def self.draftable_months(today = Date.current) = [ today.beginning_of_month, today.prev_month.beginning_of_month ]

    # "2026-10", or when an older entry already has that slug "2026-10-update", then "2026-10-update-2", ...
    def self.slug_for(period)
      month = period.starts_on.strftime("%Y-%m")
      candidates = Enumerator.new do |yielder|
        yielder << month << "#{month}#{FALLBACK_SUFFIX}"
        (2..).each { |suffix| yielder << "#{month}#{FALLBACK_SUFFIX}-#{suffix}" }
      end
      candidates.find { |slug| !Entry.where(slug:).where.not(subject: period).exists? }
    end
  end
end
