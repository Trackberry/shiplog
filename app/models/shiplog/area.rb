module Shiplog
  # A product area ("Billing", "Shipping & Tracking"): the group an entry belongs to in the changelog filter.
  # Areas are created by the AI while it rewrites entries (never beyond config.max_areas) and managed in the admin.
  class Area < ApplicationRecord
    NAME_MAX_LENGTH = 40
    NAME_FORMAT = /\A[\p{L}\p{N} &-]+\z/
    # Serialises area creation, so that concurrent rewrites cannot go past config.max_areas.
    CREATION_LOCK_KEY = Zlib.crc32("shiplog_area_creation")

    has_many :entries, class_name: "Shiplog::Entry", dependent: nil

    before_validation :normalize
    before_save :drop_translations_on_rename
    after_commit :enqueue_translation, on: %i[create update], if: :saved_change_to_name?
    before_destroy :release_entries, prepend: true

    validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }, format: { with: NAME_FORMAT }
    validates :slug, presence: true
    validate :name_translations_are_valid
    validates :name, uniqueness: { case_sensitive: false }
    validates :slug, uniqueness: true

    # The admin's order: position, then name.
    scope :ordered, -> { order(:position, :name, :id) }

    class << self
      # { area_id => number of entries }, every status and kind.
      def entry_counts = Entry.where.not(area_id: nil).group(:area_id).count

      # The existing area a name stands for: its name matched ignoring case and spacing, else its slug. Nil for
      # anything else, including non-strings.
      def resolve(name)
        return unless name.is_a?(String)

        name = name.squish
        return if name.blank?

        slug = slug_for(name)
        find_by("LOWER(name) = ?", name.downcase) || (find_by(slug:) if slug.present?)
      end

      # The URL slug of a name: parameterized, or for names parameterize empties (Cyrillic, CJK) the lowercased
      # letters and digits joined by dashes.
      def slug_for(name)
        name = name.to_s
        slug = name.parameterize
        slug = name.downcase.gsub(/[^\p{L}\p{N}]+/, "-").gsub(/\A-+|-+\z/, "") if slug.blank?
        slug.first(NAME_MAX_LENGTH)
      end

      # Enqueues a TranslateAreaJob for every area that has no name in some configured locale (`force:` as given),
      # and returns how many. Nothing without config.locales and config.rewriter.
      def enqueue_missing_translations(force: false)
        return 0 unless translatable?

        ordered.select(&:missing_translation?).each { |area| TranslateAreaJob.perform_later(area, force:) }.size
      end

      # Whether area names can be translated at all: locales are configured and there is a rewriter to ask.
      def translatable? = Shiplog.config.locales.any? && Shiplog.config.rewriter.present?

      # `resolve`, else a new area when the name is valid and fewer than config.max_areas areas exist. Nil
      # otherwise, so a caller never ends up with an invalid or surplus area. The cap is checked under a
      # transaction-level advisory lock, so concurrent callers cannot create areas past it.
      def resolve_or_create(name)
        existing = resolve(name)
        return existing if existing || !name.is_a?(String) || count >= Shiplog.config.max_areas

        area = new(name:)
        return unless area.valid?

        transaction(requires_new: true) do
          connection.execute("SELECT pg_advisory_xact_lock(#{CREATION_LOCK_KEY})")
          if (found = resolve(name)) then found # another process created it while we waited
          elsif count < Shiplog.config.max_areas && area.save then area
          end
        end
      rescue ActiveRecord::RecordNotUnique
        resolve(name) # another process created it first
      end
    end

    # The name for a locale: its translation when the locale is one of config.locales and has one, else the name.
    # Slugs are always English, so ?area= URLs are the same in every locale.
    def display_name(locale = I18n.locale)
      return name unless Entry.translated_locale?(locale)

      name_translations[locale.to_s].presence || name
    end

    # Whether some configured locale has no translated name yet.
    def missing_translation?
      Shiplog.config.locales.any? { |locale| name_translations[locale.to_s].blank? }
    end

    # Moves one place up or down in the order and renumbers all positions 0..n. Anything else is ignored. The
    # areas are read under a row lock (in order), so two moves at once renumber one after the other.
    def move(direction)
      transaction do
        areas = self.class.ordered.lock.to_a
        index = areas.index(self)
        target = { "up" => index - 1, "down" => index + 1 }[direction.to_s] if index
        next unless target && target.between?(0, areas.size - 1)

        areas[index], areas[target] = areas[target], areas[index]
        areas.each_with_index { |area, position| area.update_columns(position:) unless area.position == position }
      end
    end

    # Moves every entry to `target` and deletes this area.
    def merge_into!(target)
      raise ArgumentError, "Cannot merge an area into itself" if target == self

      transaction do
        entries.update_all(area_id: target.id, updated_at: Time.current)
        destroy!
      end
    end

    private

    def normalize
      self.name = name.squish if name
      if name_translations.is_a?(Hash)
        self.name_translations = name_translations.to_h { |locale, value| [ locale.to_s, value.is_a?(String) ? Rewriter.sanitize(value).squish : value ] }
          .reject { |_locale, value| value.nil? || value == "" }
      end
      self.slug = self.class.slug_for(name)
      self.position = (self.class.maximum(:position) || -1) + 1 if new_record? && position.to_i.zero? && self.class.exists?
    end

    # A renamed area's translations are of the old name: drop them (the job translates the new one), unless the
    # same save sets translations itself.
    def drop_translations_on_rename
      self.name_translations = {} if persisted? && name_changed? && !name_translations_changed?
    end

    def name_translations_are_valid
      return errors.add(:name_translations, :invalid) unless name_translations.is_a?(Hash)

      name_translations.each do |locale, value|
        valid = value.is_a?(String) && value.length <= NAME_MAX_LENGTH && NAME_FORMAT.match?(value)
        errors.add(:name_translations, "#{locale}: #{value.inspect.truncate(60)} is not a valid name") unless valid
      end
    end

    def enqueue_translation
      TranslateAreaJob.perform_later(self) if self.class.translatable?
    end

    # Entries of a deleted area have no area (the foreign key nullifies it too); the admin's choice went with it.
    def release_entries
      entries.update_all(area_id: nil, area_set_by_admin: false, updated_at: Time.current)
    end
  end
end
