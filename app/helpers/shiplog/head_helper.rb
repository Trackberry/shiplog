module Shiplog
  # The data side of `<%= shiplog_head_tags %>` (see HeadTagsHelper, the only helper every view gets). Included
  # in the engine's public controllers only.
  #
  # The views declare their page with #shiplog_head_page (which also fills the older `content_for` blocks, kept
  # for backward compatibility); the partials below are overridable by the host app:
  #   shiplog/_head_tags             renders the four below
  #   shiplog/head/_meta             description, canonical, robots
  #   shiplog/head/_open_graph       og:* and twitter:*
  #   shiplog/head/_feed             the Atom alternate link
  #   shiplog/head/_structured_data  the JSON-LD script
  # Each receives the locals `head` (a Hash: :kind, :title, :entry, :canonical, :image, :description), `description`,
  # `canonical`, `robots`, `open_graph` and `twitter` (Hashes of tag name => content), `feed_url`, `feed_title`
  # and `json_ld`. Whatever `except:` removed arrives as nil or an empty Hash.
  module HeadHelper
    # Renders the head tags of the current page, leaving out the `skip` groups (see HeadTagsHelper, which
    # validates and guards). An empty string when the page declared none.
    def shiplog_render_head_tags(skip)
      return "".html_safe unless @shiplog_head

      render(partial: "shiplog/head_tags", locals: shiplog_head_locals(skip))
    end

    # Declares the page for shiplog_head_tags and fills the older content_for blocks (which shiplog_head_tags
    # never reads). `kind` is :permalink,
    # :changelog or :roadmap; the rest is what the page computed: entry (permalink), title, url (the page's
    # absolute URL, nil for a search), query (a search), json_ld, feed (whether it advertises the Atom feed).
    def shiplog_head_page(kind, title:, url: nil, entry: nil, query: nil, json_ld: nil, feed: true)
      @shiplog_head = { kind:, title:, url:, entry:, query:, json_ld:, feed: }
      shiplog_fill_legacy_blocks
    end

    private

    def shiplog_fill_legacy_blocks
      head = @shiplog_head
      entry = head[:entry]
      blocks = {
        shiplog_description: (shiplog_entry_description(entry) if entry),
        shiplog_og: (shiplog_og_tags(entry, url: head[:url]) if entry),
        shiplog_robots: ("noindex" if head[:query]),
        shiplog_feed: shiplog_head_feed_link(head),
        shiplog_structured_data: head[:json_ld]
      }
      blocks.each { |name, value| content_for(name, value) if value.present? }
    end

    def shiplog_head_feed_link(head)
      return unless head[:feed]

      auto_discovery_link_tag(:atom, shiplog_absolute_url(:changelog_feed), title: shiplog_feed_title)
    end

    def shiplog_feed_title = t("shiplog.feed.link_title", default: "Changelog (Atom)")

    def shiplog_head_locals(skip)
      head = @shiplog_head
      entry = head[:entry]
      # A search page has no canonical: it is noindex, and noindex with a canonical sends search engines two
      # signals that disagree.
      canonical = head[:url] unless head[:query]
      image = shiplog_entry_og_image(entry) if entry
      description = shiplog_entry_description(entry) if entry
      page = head.slice(:kind, :title, :entry).merge(canonical:, image:, description:)

      {
        head: page,
        description: (description unless skip.include?(:description)),
        canonical: (canonical unless skip.include?(:canonical)),
        robots: ("noindex" if head[:query] && !skip.include?(:robots)),
        open_graph: (skip.include?(:open_graph) ? {} : shiplog_head_open_graph(head, canonical, image, description)),
        twitter: (skip.include?(:twitter) ? {} : shiplog_head_twitter(image)),
        feed_url: (shiplog_absolute_url(:changelog_feed) if head[:feed] && !skip.include?(:feed)),
        feed_title: shiplog_feed_title,
        json_ld: (head[:json_ld] unless skip.include?(:structured_data))
      }
    end

    def shiplog_head_open_graph(head, canonical, image, description)
      entry = head[:entry]
      {
        "og:title" => (entry ? entry.display_title : head[:title]),
        "og:description" => description,
        "og:type" => (entry ? "article" : "website"),
        "og:url" => canonical,
        "og:image" => image,
        "og:image:alt" => (entry.display_title if image)
      }.compact_blank
    end

    def shiplog_head_twitter(image)
      { "twitter:card" => (image ? "summary_large_image" : "summary"), "twitter:image" => image }.compact_blank
    end
  end
end
