module Shiplog
  # Constants of shiplog_head_tags. Not included anywhere, so views of the host cannot see them.
  module HeadTags
    EXCEPT_KEYS = %i[description canonical robots open_graph twitter feed structured_data].freeze
  end

  # The one helper added to every view of the host (like a pagination gem's `paginate`), so a layout shared
  # with the host's own pages can call `shiplog_head_tags`. The rest lives in Shiplog::HeadHelper, which only
  # the engine's controllers include.
  #
  # This file is required by lib/shiplog.rb rather than autoloaded: the engine includes the module into
  # ActionView::Base from an on_load hook, which can run during boot before the autoloaders are set up, and
  # ActionView::Base never reloads, so the module must not either.
  module HeadTagsHelper
    # The head tags of the current Shiplog page; an empty string on any other page. `except:` leaves groups
    # out, for tags your layout already writes: :description, :canonical, :robots, :open_graph, :twitter,
    # :feed, :structured_data. An unknown key raises ArgumentError.
    #
    # Call it in the layout, not inside a component (ViewComponent, Phlex): there it gives an empty string.
    # Use it OR the older `content_for :shiplog_*` blocks in a layout, not both: both would emit the tags twice.
    def shiplog_head_tags(except: [])
      keys = Array(except).map { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
      unknown = keys - HeadTags::EXCEPT_KEYS
      if unknown.any?
        raise ArgumentError, "Unknown shiplog_head_tags except: key(s) #{unknown.map(&:inspect).join(", ")}. Valid keys: #{HeadTags::EXCEPT_KEYS.map(&:inspect).join(", ")}"
      end
      # A marker, not is_a?(Shiplog::PublicController): that would autoload the controller (and the host's
      # parent controller) on every host page. Views that don't have the engine's helper (components) skip too.
      return "".html_safe unless controller.respond_to?(:shiplog_public_page?) && respond_to?(:shiplog_render_head_tags, true)

      shiplog_render_head_tags(keys)
    end
  end
end
