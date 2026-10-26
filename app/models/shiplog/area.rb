module Shiplog
  # A product area ("Billing", "Shipping & Tracking"): the group an entry belongs to in the changelog filter.
  # Areas are created by the AI while it rewrites entries (never beyond config.max_areas) and managed in the admin.
  class Area < ApplicationRecord
    NAME_MAX_LENGTH = 40
    NAME_FORMAT = /\A[\p{L}\p{N} &-]+\z/

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

        slug = name.parameterize
        find_by("LOWER(name) = ?", name.downcase) || (find_by(slug:) if slug.present?)
      end

      # `resolve`, else a new area when the name is valid and fewer than config.max_areas areas exist. Nil
      # otherwise, so a caller never ends up with an invalid or surplus area.
      def resolve_or_create(name)
        existing = resolve(name)
        return existing if existing || !name.is_a?(String) || count >= Shiplog.config.max_areas

        area = new(name:)
        return unless area.valid?

        transaction(requires_new: true) { area.save! }
        area
      rescue ActiveRecord::RecordNotUnique
        resolve(name) # another process created it first
      end
    end

    # Moves one place up or down in the order and renumbers all positions 0..n. Anything else is ignored.
    def move(direction)
      areas = self.class.ordered.to_a
      index = areas.index(self)
      target = { "up" => index - 1, "down" => index + 1 }[direction.to_s] if index
      return unless target && target.between?(0, areas.size - 1)

      areas[index], areas[target] = areas[target], areas[index]
      transaction { areas.each_with_index { |area, position| area.update_columns(position:) unless area.position == position } }
    end

    # Moves every entry to `target` and deletes this area.
    def merge_into!(target)
      raise ArgumentError, "Cannot merge an area into itself" if target == self

      transaction do
        entries.update_all(area_id: target.id)
        destroy!
      end
    end

    private

    def normalize
      self.name = name.squish if name
      self.slug = name.to_s.parameterize
      self.position = (self.class.maximum(:position) || -1) + 1 if new_record? && position.to_i.zero? && self.class.exists?
    end

    # Entries of a deleted area have no area (the foreign key nullifies it too); the admin's choice went with it.
    def release_entries
      entries.update_all(area_id: nil, area_set_by_admin: false)
    end
  end
end
