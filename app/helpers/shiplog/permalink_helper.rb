module Shiplog
  # Markup helpers of the permalink pages and the Atom feed. The two hooks at the bottom are where later
  # features add an entry's first image (Open Graph) and its images (feed content).
  module PermalinkHelper
    DESCRIPTION_LENGTH = 160

    # The path of an entry's permalink page, or nil when the entry has no slug the route accepts (a link is
    # an extra, never a reason to fail the page).
    def shiplog_entry_path(entry)
      changelog_entry_path(entry.slug) if entry.permalink?
    rescue ActionController::UrlGenerationError
      nil
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

    # Hook: the absolute URL of the image to show when the page is shared, or nil.
    def shiplog_entry_og_image(_entry) = nil

    # The HTML of an entry in the Atom feed. Hook: images are added here.
    def shiplog_feed_content(entry) = simple_format(h(entry.body))
  end
end
