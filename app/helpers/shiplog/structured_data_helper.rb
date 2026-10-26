module Shiplog
  # schema.org structured data (JSON-LD) of the public pages, for `content_for :shiplog_structured_data`.
  # Every method returns nil while config.structured_data is off, or when there is nothing worth describing.
  module StructuredDataHelper
    HEADLINE_LENGTH = 110
    CONTEXT = "https://schema.org".freeze
    # "<", ">" and "&" (and the line separators JavaScript treats as newlines) become JSON \u escapes: still the
    # same string once parsed, but a "</script>" in a title cannot close the tag.
    SCRIPT_ESCAPES = { "<" => "\\u003c", ">" => "\\u003e", "&" => "\\u0026", " " => "\\u2028", " " => "\\u2029" }.freeze

    # A <script type="application/ld+json"> tag for a Hash, or nil while structured data is off.
    def shiplog_json_ld(data)
      return unless Shiplog.config.structured_data && data

      json = JSON.generate(data).gsub(/[<>&  ]/, SCRIPT_ESCAPES)
      # Safe: JSON.generate output with every character that could end the script element escaped above.
      content_tag(:script, json.html_safe, type: "application/ld+json")
    end

    # The Article of a permalink page.
    def shiplog_article_json_ld(entry)
      return unless Shiplog.config.structured_data

      url = shiplog_entry_url(entry)
      images = shiplog_images(entry).filter_map { |image| shiplog_image_url(image) }
      shiplog_json_ld({
        "@context" => CONTEXT, "@type" => "Article",
        "headline" => truncate(entry.display_title.to_s.squish, length: HEADLINE_LENGTH, escape: false),
        "description" => shiplog_entry_description(entry, escape: false).presence,
        "inLanguage" => I18n.locale.to_s,
        "datePublished" => entry.released_on&.iso8601, "dateModified" => entry.updated_at&.iso8601,
        "url" => url, "mainEntityOfPage" => url,
        "image" => images.presence,
        "articleSection" => entry.area&.display_name.presence,
        "publisher" => shiplog_publisher_json_ld,
        "isPartOf" => { "@type" => "CollectionPage", "url" => shiplog_absolute_url(:changelog) }
      }.compact)
    end

    # The CollectionPage of the changelog list: an ItemList of the entries shown. Nil for search results and an
    # empty list.
    def shiplog_changelog_json_ld(entries, name:, url:)
      return if @query

      items = entries.filter_map { |entry| [ shiplog_entry_url(entry), entry.display_title ] if entry.permalink? }
      return if items.empty?

      shiplog_collection_json_ld(name:, url:, items: items.map { |item_url, title| { "url" => item_url, "name" => title } })
    end

    # The CollectionPage of the roadmap: an ItemList of the cards, which have no URL.
    def shiplog_roadmap_json_ld(entries, name:, url:)
      return if entries.empty?

      shiplog_collection_json_ld(name:, url:, items: entries.map { |entry| { "name" => entry.display_title } })
    end

    private

    def shiplog_collection_json_ld(name:, url:, items:)
      elements = items.each_with_index.map { |item, index| { "@type" => "ListItem", "position" => index + 1, **item } }
      shiplog_json_ld({
        "@context" => CONTEXT, "@type" => "CollectionPage", "name" => name, "url" => url, "inLanguage" => I18n.locale.to_s,
        "mainEntity" => { "@type" => "ItemList", "itemListElement" => elements }
      })
    end

    def shiplog_publisher_json_ld
      name = Shiplog.config.product_name.presence
      { "@type" => "Organization", "name" => name } if name
    end
  end
end
