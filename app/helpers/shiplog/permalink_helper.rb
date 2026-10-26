module Shiplog
  # Markup helpers of the permalink pages, the Atom feed and the entries' screenshots.
  module PermalinkHelper
    DESCRIPTION_LENGTH = 160

    # The path of an entry's permalink page, or nil when the entry has no slug the route accepts (a link is
    # an extra, never a reason to fail the page).
    def shiplog_entry_path(entry)
      changelog_entry_path(entry.slug) if entry.permalink?
    rescue ActionController::UrlGenerationError
      nil
    end

    # The absolute URL of a named engine route: config.canonical_url plus the route's path (which carries the
    # engine's mount prefix) when it is set, the request's own origin otherwise.
    #   shiplog_absolute_url(:changelog_feed)  # => "https://trackberry.com/changelog.atom"
    def shiplog_absolute_url(route, *args)
      canonical = Shiplog.config.canonical_url
      canonical ? "#{canonical}#{public_send("#{route}_path", *args)}" : public_send("#{route}_url", *args)
    end

    # The absolute URL of an entry's permalink page, or nil when it has no valid slug.
    def shiplog_entry_url(entry)
      shiplog_absolute_url(:changelog_entry, entry.slug) if shiplog_entry_path(entry)
    end

    # The authority of the feed's tag URIs: the canonical host, else the request's.
    def shiplog_tag_host
      canonical = Shiplog.config.canonical_url
      canonical ? URI.parse(canonical).host : request.host
    end

    # A link to an entry's permalink page, or the plain content in a span when it has none.
    def shiplog_entry_link(entry, name = nil, html_options = {}, &block)
      name, html_options = capture(&block), name || {} if block
      path = shiplog_entry_path(entry)
      path ? link_to(name, path, html_options) : content_tag(:span, name, html_options.slice(:class))
    end

    # The id of a month's section on the changelog list.
    def shiplog_month_anchor(date) = "shiplog-month-#{date.strftime("%Y-%m")}"

    # The body, on one line and cut for a meta description. Plain text: tag helpers escape it.
    def shiplog_entry_description(entry)
      truncate(entry.body.to_s.squish, length: DESCRIPTION_LENGTH, separator: " ")
    end

    # The Open Graph meta tags of a permalink page, for `content_for :shiplog_og`.
    def shiplog_og_tags(entry, url:)
      tags = {
        "og:title" => entry.title, "og:description" => shiplog_entry_description(entry),
        "og:type" => "article", "og:url" => url, "og:image" => shiplog_entry_og_image(entry)
      }
      safe_join(tags.compact_blank.map { |property, content| tag.meta(property:, content:) }, "\n")
    end

    # The absolute URL of the image to show when the page is shared (the first image), or nil.
    def shiplog_entry_og_image(entry)
      image = shiplog_images(entry).first
      shiplog_image_url(image) if image
    end

    # The HTML of an entry in the Atom feed: its text, then its images with absolute URLs.
    def shiplog_feed_content(entry)
      images = shiplog_images(entry).filter_map do |image|
        url = shiplog_image_url(image)
        tag.p(tag.img(src: url, alt: entry.image_alt(image), **shiplog_image_size(image))) if url
      end
      safe_join([ simple_format(h(entry.body)), *images ], "\n")
    end

    # An entry's images in order, or none while screenshots are off.
    def shiplog_images(entry)
      Shiplog.images? ? entry.ordered_images : []
    end

    # The images of an entry under its body: `limit` of them (all by default). Nil when it has none to show.
    def shiplog_entry_images(entry, limit: nil)
      images = shiplog_images(entry)
      images = images.first(limit) if limit
      tags = images.filter_map do |image|
        path = shiplog_image_path(image)
        tag.img(src: path, alt: entry.image_alt(image), loading: "lazy", class: shiplog_class(:entry_image), **shiplog_image_size(image)) if path
      end
      tag.div(safe_join(tags), class: shiplog_class(:entry_images)) if tags.any?
    end

    # Active Storage's routes belong to the host: url_for reaches them through main_app (see HostRoutesHelper).
    # Nil when the host can't build the route.
    def shiplog_image_path(image)
      polymorphic_path(image)
    rescue ActionController::UrlGenerationError, NoMethodError, ArgumentError
      nil
    end

    # The image's absolute URL: config.canonical_url plus its path when set, the request's origin otherwise.
    def shiplog_image_url(image)
      canonical = Shiplog.config.canonical_url
      return polymorphic_url(image) unless canonical

      path = shiplog_image_path(image)
      "#{canonical}#{path}" if path
    rescue ActionController::UrlGenerationError, NoMethodError, ArgumentError
      nil
    end

    # width and height from the blob's analysis, when it has run and found them.
    def shiplog_image_size(image)
      metadata = image.blob.metadata
      { width: metadata[:width], height: metadata[:height] }.select { |_, value| value.to_i.positive? }
    end
  end
end
