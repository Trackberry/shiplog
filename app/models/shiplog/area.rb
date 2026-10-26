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
    before_destroy :release_entries, prepend: true

    validates :name, presence: true, length: { maximum: NAME_MAX_LENGTH }, format: { with: NAME_FORMAT }
    validates :slug, presence: true
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
      self.slug = self.class.slug_for(name)
      self.position = (self.class.maximum(:position) || -1) + 1 if new_record? && position.to_i.zero? && self.class.exists?
    end

    # Entries of a deleted area have no area (the foreign key nullifies it too); the admin's choice went with it.
    def release_entries
      entries.update_all(area_id: nil, area_set_by_admin: false, updated_at: Time.current)
    end
  end
end
