# The latest published features and changes. Entry ids are tag URIs built from the permalink path, so they
# stay the same when a title changes.
title = Shiplog.config.product_name.present? ? t("shiplog.feed.title_with_product", product: Shiplog.config.product_name, default: "%{product} changelog") : t("shiplog.changelog.title", default: "Changelog")

atom_feed(language: I18n.locale.to_s, url: changelog_feed_url, root_url: changelog_url) do |feed|
  feed.title(title)
  feed.updated(@entries.map(&:updated_at).max || Time.current)

  @entries.each do |entry|
    feed.entry(entry, id: "tag:#{request.host},2005:#{changelog_entry_path(entry.slug)}", url: changelog_entry_url(entry.slug),
        published: entry.released_on.in_time_zone, updated: entry.updated_at) do |item|
      item.title(entry.title.to_s)
      item.category(term: entry.area.slug, label: entry.area.name) if entry.area
      item.content(shiplog_feed_content(entry), type: "html")
    end
  end
end
