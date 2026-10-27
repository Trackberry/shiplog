module Shiplog
  # One calendar month: the subject of a monthly announcement entry (kind "announcement"). Shiplog::Entry keeps
  # its polymorphic subject, and its unique (subject, kind) index makes drafting a month idempotent.
  #
  # Like an issue or a pull request, a period has a `title` and a `body`, which Drafter copies into a new draft:
  # the month's name and a Markdown skeleton listing the month's entries. Without a rewriter, that skeleton is
  # the draft; with one, the AI's text replaces it (see Rewriter::AnnouncementPrompt).
  class Period < ApplicationRecord
    # How many entries and skipped changes the skeleton and the prompt list at most.
    MAX_ENTRIES = 60
    MAX_SKIPPED = 60
    SKELETON_DEFAULTS = { features: "New", also_improved: "Also improved" }.freeze

    has_many :entries, as: :subject, dependent: :destroy

    validates :starts_on, :ends_on, presence: true

    # The period of the month containing `date`, created when it does not exist yet.
    def self.month(date)
      starts_on = date.to_date.beginning_of_month
      create_or_find_by!(starts_on:) { |period| period.ends_on = starts_on.end_of_month }
    end

    # Approved features and changes released within `range` (dates): what an announcement is made of.
    def self.changelog_entries_between(range)
      Entry.published_changelog.where(released_on: range)
    end

    def range = starts_on..ends_on

    # The month's announcement, or nil.
    def announcement = entries.find_by(kind: "announcement")

    # The month's approved features and changes, features first, then in release order.
    def changelog_entries
      self.class.changelog_entries_between(range).includes(:area).in_order_of(:kind, %w[feature change])
        .order(:released_on, :id).limit(MAX_ENTRIES)
    end

    # The titles of the month's small changes that got no entry of their own, for an "Also improved" line: changes
    # the AI judged not customer-facing (an admin's discard is deliberate and left out), then merged pull requests
    # of changelog repositories with no entry at all (an excluded Conventional Commits type keeps them out of the
    # changelog). Pull requests with an excluded label or author stay out here too: `internal` means internal.
    def skipped_change_titles
      discarded = Entry.discarded.where(kind: "change", released_on: range, discard_reason: Rewriter::NOT_CUSTOMER_FACING)
        .order(:released_on, :id).limit(MAX_SKIPPED).pluck(:title)
      (discarded + skipped_pull_request_titles(MAX_SKIPPED - discarded.size)).compact_blank.uniq
    end

    # The month's name in the default locale ("October 2026"), the title of a new draft. English when that locale
    # has no month names (I18n then returns a "Translation missing" string rather than raising).
    def title
      locale = I18n.default_locale
      return starts_on.strftime("%B %Y") unless I18n.exists?(:"date.month_names", locale)

      I18n.l(starts_on, format: "%B %Y", locale:)
    rescue I18n::ArgumentError
      starts_on.strftime("%B %Y")
    end

    # The Markdown skeleton of the month in the default locale: the features, then "Also improved" with the
    # changes grouped by area, each linking to its permalink page (see PublicLinks).
    def body
      features, changes = changelog_entries.to_a.partition(&:feature?)
      I18n.with_locale(I18n.default_locale) do
        sections = []
        sections << "## #{skeleton_text(:features)}\n\n#{list(features)}" if features.any?
        sections << [ "## #{skeleton_text(:also_improved)}", *grouped_by_area(changes) ].join("\n\n") if changes.any?
        sections.join("\n\n")
      end
    end

    # The digest of what an announcement is drafted from: the ids and last update of the month's entries. A draft
    # whose stored digest differs is flagged "entries changed since this draft" in the admin.
    def content_digest
      rows = self.class.changelog_entries_between(range).order(:id).pluck(:id, :updated_at)
      Digest::SHA256.hexdigest(JSON.generate(rows.map { |id, updated_at| [ id, updated_at.utc.iso8601(6) ] }))
    end

    # A period has no page on GitHub (see Admin::EntriesHelper).
    def url = nil

    private

    # Merged pull requests of the month in changelog repositories that have no entry, without excluded labels or
    # authors, oldest first. Pull requests of a public issue's tree are left out: its feature covers them, and an
    # unshipped one must not be announced.
    def skipped_pull_request_titles(limit)
      return [] unless limit.positive?

      config = Shiplog.config
      names = config.repository_names.select { |name| config.changelog_repository?(name) }
      PullRequest.where(repository: Repository.where(full_name: names), state: "merged",
        merged_at: starts_on.in_time_zone...(ends_on + 1).in_time_zone)
        .where.missing(:entries).order(:merged_at, :id).limit(limit * 3).to_a
        .reject { |pull_request| pull_request.labels.intersect?(config.excluded_labels) || config.excluded_author?(pull_request.author_login) }
        .then { |candidates| without_public_tree(candidates) }
        .first(limit).map(&:title)
    end

    def without_public_tree(pull_requests)
      ids = ChangeCandidates.public_tree_pull_request_ids(pull_requests)
      pull_requests.reject { |pull_request| ids.include?(pull_request.node_id) }
    end

    # Changes without an area first, then one "###" group per area, in the admin's order.
    def grouped_by_area(changes)
      groups = changes.group_by(&:area)
      ungrouped = groups.delete(nil)
      areas = groups.sort_by { |area, _| [ area.position, area.id ] }.map { |area, items| "### #{area.name}\n\n#{list(items)}" }
      [ (list(ungrouped) if ungrouped), *areas ].compact
    end

    def list(entries) = entries.map { |entry| "- #{item(entry)}" }.join("\n")

    # "[Title](url): the body's first sentence", the link only when the entry has a permalink.
    def item(entry)
      url = PublicLinks.entry_url(entry)
      title = entry.title.to_s.squish.delete("[]")
      summary = entry.body.to_s.squish.split(Rewriter::SENTENCE_END, 2).first.to_s.strip
      text = url ? "[#{title}](#{url})" : title
      summary.present? ? "#{text}: #{summary}." : text
    end

    def skeleton_text(key) = I18n.t("shiplog.announcements.skeleton.#{key}", default: SKELETON_DEFAULTS.fetch(key))
  end
end
