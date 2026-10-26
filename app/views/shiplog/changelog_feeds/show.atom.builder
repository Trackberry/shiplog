# The latest published features and changes. Entry ids are tag URIs built from the permalink path, so they
# stay the same when a title changes.
title = Shiplog.config.product_name.present? ? t("shiplog.feed.title_with_product", product: Shiplog.config.product_name, default: "%{product} changelog") : t("shiplog.changelog.title", default: "Changelog")

atom_feed(language: I18n.locale.to_s, url: shiplog_absolute_url(:changelog_feed), root_url: shiplog_absolute_url(:changelog),
    id: "tag:#{shiplog_tag_host},2005:#{changelog_path}") do |feed|
  feed.title(title)
  feed.author { |author| author.name(Shiplog.config.product_name.presence || "Changelog") } # RFC 4287 4.1.1: the feed or each entry needs one
  # An entry is updated when its text or the translation shown in this feed changes.
  updated_at = ->(entry) { [ entry.updated_at, entry.translation&.updated_at ].compact.max }
  feed.updated(@entries.map(&updated_at).max || Time.current)

  @entries.each do |entry|
    feed.entry(entry, id: "tag:#{shiplog_tag_host},2005:#{shiplog_entry_path(entry)}", url: shiplog_entry_url(entry),
        published: entry.released_on.in_time_zone, updated: updated_at.(entry)) do |item|
      item.title(entry.display_title.to_s)
      item.category(term: entry.area.slug, label: entry.area.name) if entry.area
      item.content(shiplog_feed_content(entry), type: "html")
    end
  end
end
