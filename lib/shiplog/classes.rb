module Shiplog
  # The public styling hooks. Every element of the public pages has a key here, a stable BEM class
  # (always rendered) and an optional host-supplied class string (config.classes[key]).
  module Classes
    BEM = {
      page: "shiplog-page",
      page_header: "shiplog-page__header",
      page_title: "shiplog-page__title",
      page_lede: "shiplog-page__lede",
      switcher: "shiplog-switcher",
      switcher_link: "shiplog-switcher__link",
      columns: "shiplog-columns",
      column: "shiplog-column",
      column_header: "shiplog-column__header",
      column_title: "shiplog-column__title",
      column_count: "shiplog-column__count",
      column_description: "shiplog-column__description",
      column_empty: "shiplog-column__empty",
      cards: "shiplog-cards",
      card: "shiplog-card",
      card_title: "shiplog-card__title",
      card_body: "shiplog-card__body",
      months: "shiplog-months",
      month: "shiplog-month",
      month_title: "shiplog-month__title",
      entries: "shiplog-entries",
      entry: "shiplog-entry",
      entry_feature: "shiplog-entry--feature",
      entry_category: "shiplog-entry__category",
      entry_title: "shiplog-entry__title",
      entry_body: "shiplog-entry__body",
      entry_date: "shiplog-entry__date",
      pagination: "shiplog-pagination",
      pagination_link: "shiplog-pagination__link",
      empty: "shiplog-empty"
    }.freeze

    KEYS = BEM.keys.freeze
  end
end
