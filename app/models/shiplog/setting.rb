module Shiplog
  # A small key-value store (a JSON object per key) for state that belongs to no record, e.g. the last area detection.
  class Setting < ApplicationRecord
    validates :key, presence: true, uniqueness: true

    class << self
      # The Hash stored under `key` (string keys), or nil.
      def read(key) = find_by(key:)&.value

      # Stores the given attributes as the whole value under `key`.
      def write(key, **value)
        record = find_or_initialize_by(key:)
        record.update!(value: value.stringify_keys)
      rescue ActiveRecord::RecordNotUnique
        retry
      end
    end
  end
end
