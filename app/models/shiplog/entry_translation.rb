module Shiplog
  # An entry's title and body in one locale (config.locales), published with the English text. `source_digest`
  # is the digest of the English title and body it was made from (Entry#translation_source_digest); once the
  # English text differs, the row is stale and the public pages show English instead. `edited_by_admin` marks a
  # text an admin changed, which a new translation only replaces when the English text changed.
  class EntryTranslation < ApplicationRecord
    belongs_to :entry, class_name: "Shiplog::Entry", inverse_of: :translations

    validates :locale, :title, :source_digest, presence: true
    validates :locale, uniqueness: { scope: :entry_id }

    # Whether the English text has changed since this translation was made.
    def stale? = source_digest != entry.translation_source_digest
  end
end
