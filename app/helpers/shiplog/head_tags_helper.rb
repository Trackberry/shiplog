module Shiplog
  # The one helper added to every view of the host (like a pagination gem's `paginate`), so a layout shared
  # with the host's own pages can call `shiplog_head_tags`. The rest lives in Shiplog::HeadHelper, which only
  # the engine's controllers include.
  module HeadTagsHelper
    EXCEPT_KEYS = %i[description canonical robots open_graph twitter feed structured_data].freeze

    # The head tags of the current Shiplog page; an empty string on any other page. `except:` leaves groups
    # out, for tags your layout already writes: :description, :canonical, :robots, :open_graph, :twitter,
    # :feed, :structured_data. An unknown key raises ArgumentError.
    #
    # Use it OR the older `content_for :shiplog_*` blocks in a layout, not both: both would emit the tags twice.
    def shiplog_head_tags(except: [])
      keys = Array(except).map { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
      unknown = keys - EXCEPT_KEYS
      if unknown.any?
        raise ArgumentError, "Unknown shiplog_head_tags except: key(s) #{unknown.map(&:inspect).join(", ")}. Valid keys: #{EXCEPT_KEYS.map(&:inspect).join(", ")}"
      end
      return "".html_safe unless controller.is_a?(Shiplog::PublicController)

      shiplog_render_head_tags(keys)
    end
  end
end
