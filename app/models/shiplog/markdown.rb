module Shiplog
  # A small, dependency-free Markdown subset for announcement bodies (written by an LLM, edited by an admin, shown
  # on public pages, in the feed and in emails). XSS-safe by construction: every piece of source text is escaped
  # before it is placed in a tag we build ourselves, and raw HTML is never passed through.
  module Markdown
    HEADING = /\A {0,3}(\#{1,6})[ \t]+(.*?)(?:[ \t]+\#+)?[ \t]*\z/
    RULE = /\A {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*\z/
    ITEM = /\A([ \t]*)([-*+]|\d+[.)])[ \t]+(.*)\z/
    QUOTE = /\A {0,3}>[ \t]?(.*)\z/
    LINK = /\G\[((?:\\.|[^\]\\])*)\]\(((?:[^()\\]|\\.|\([^()]*\))*)\)/
    IMAGE = /\G!\[((?:\\.|[^\]\\])*)\]\(((?:[^()\\]|\\.|\([^()]*\))*)\)/
    ESCAPABLE = %w[* _ [ ] ( ) ` \\ # ! -].freeze
    LINK_URL = %r{\A(?:https?://|mailto:|#|/(?![/\\]))}i
    IMAGE_URL = %r{\A(?:https?://|/(?![/\\]))}i
    CONTROL_CHARS = /[[:cntrl:]]/

    # Block-level HTML for +text+. Heading levels are shifted by +heading_offset+ (clamped to h1..h6). +styles+
    # maps tag names to inline styles ({ "p" => "margin:0 0 12px;" }) for emails, where stylesheets are ignored.
    def self.to_html(text, heading_offset: 0, styles: {})
      html = blocks(text).map { |block| render_block_html(block, heading_offset, styles) }.join("\n")
      html.html_safe # every fragment was escaped or built by us
    end

    # Plain text (no HTML escaping) for emails and meta descriptions; blocks are separated by a blank line.
    def self.to_text(text)
      blocks(text).filter_map { |block| render_block_text(block) }.join("\n\n")
    end

    # Splits the source into [:heading, level, text], [:paragraph, text], [:quote, text], [:list, ordered, items]
    # and [:rule] blocks.
    def self.blocks(text)
      lines = text.to_s.gsub(/\r\n?/, "\n").split("\n")
      result = []
      until lines.empty?
        line = lines.first
        if line.strip.empty?
          lines.shift
        elsif (match = line.match(HEADING))
          lines.shift
          result << [ :heading, match[1].length, match[2] ]
        elsif line.match?(RULE)
          lines.shift
          result << [ :rule ]
        elsif line.match?(ITEM)
          result << take_list(lines)
        elsif line.match?(QUOTE)
          result << [ :quote, take_while(lines) { |l| l.match(QUOTE)&.[](1) }.join("\n") ]
        else
          result << [ :paragraph, take_paragraph(lines).join("\n").strip ]
        end
      end
      result
    end
    private_class_method :blocks

    def self.block_start?(line)
      line.match?(HEADING) || line.match?(RULE) || line.match?(ITEM) || line.match?(QUOTE)
    end
    private_class_method :block_start?

    # Shifts consecutive lines for which the block returns a (non-nil) value, and returns those values.
    def self.take_while(lines)
      taken = []
      while lines.any? && (value = yield(lines.first))
        taken << value
        lines.shift
      end
      taken
    end
    private_class_method :take_while

    def self.take_paragraph(lines)
      [ lines.shift ] + take_while(lines) { |l| l unless l.strip.empty? || block_start?(l) }
    end
    private_class_method :take_paragraph

    # Items of one list kind. Indented items continue the list, indented non-item lines continue the last item, and
    # blank lines are skipped only when the next non-blank line is another item of the same kind.
    def self.take_list(lines)
      ordered = ordered_item?(lines.first)
      items = []
      until lines.empty?
        line = lines.first
        if line.strip.empty?
          following = lines.find { |l| !l.strip.empty? }
          break unless following&.match?(ITEM) && !following.match?(RULE) && ordered_item?(following) == ordered
          lines.shift
        elsif line.match?(RULE) || (line.match?(ITEM) && ordered_item?(line) != ordered)
          break
        elsif (match = line.match(ITEM))
          items << match[3].strip
          lines.shift
        elsif line.match?(/\A[ \t]+\S/) && !line.match?(HEADING) && !line.match?(QUOTE)
          items[-1] = "#{items.last}\n#{line.strip}"
          lines.shift
        else
          break
        end
      end
      [ :list, ordered, items ]
    end
    private_class_method :take_list

    def self.ordered_item?(line) = line.match(ITEM)[2].match?(/\d/)
    private_class_method :ordered_item?

    # In HTML mode, +styles+ (a Hash, maybe empty) stands for the html flag of the inline renderers.
    def self.render_block_html(block, heading_offset, styles)
      case block.first
      when :heading
        level = (block[1] + heading_offset).clamp(1, 6)
        "#{open("h#{level}", styles)}#{inline(block[2], styles)}</h#{level}>"
      when :paragraph then "#{open("p", styles)}#{inline(block[1], styles)}</p>"
      when :quote then "#{open("blockquote", styles)}#{open("p", styles)}#{inline(block[1], styles)}</p></blockquote>"
      when :rule then open("hr", styles)
      when :list
        tag = block[1] ? "ol" : "ul"
        items = block[2].map { |item| "#{open("li", styles)}#{inline(item, styles)}</li>" }.join("\n")
        "#{open(tag, styles)}\n#{items}\n</#{tag}>"
      end
    end
    private_class_method :render_block_html

    # "<p>" or, with an inline style for the tag, "<p style="...">" (the style escaped like any attribute).
    def self.open(tag, styles) = "<#{tag}#{style(tag, styles)}>"
    private_class_method :open

    def self.style(tag, styles)
      value = styles[tag] if styles.is_a?(Hash)
      value.present? ? %( style="#{escape(value, true)}") : ""
    end
    private_class_method :style

    def self.render_block_text(block)
      case block.first
      when :heading then inline(block[2], false)
      when :paragraph, :quote then inline(block[1], false)
      when :list
        block[2].each_with_index.map { |item, i| "#{block[1] ? "#{i + 1}." : "-"} #{inline(item, false)}" }.join("\n")
      end
    end
    private_class_method :render_block_text

    # Scans left to right; whatever is not a recognised construct is literal (and escaped in HTML mode).
    def self.inline(source, html)
      out = +""
      i = 0
      while i < source.length
        output, i = inline_token(source, i, html)
        out << output
      end
      out
    end
    private_class_method :inline

    # Consumes one construct (or one literal character) at index +i+; returns its output and the next index.
    def self.inline_token(source, i, html)
      char = source[i]
      if char == "\\" && ESCAPABLE.include?(source[i + 1])
        [ escape(source[i + 1], html), i + 2 ]
      elsif char == "`" && source[i + 1] == "`"
        run = source[i..][/\A`+/]
        [ run, i + run.length ] # a run of backticks (such as a ``` fence) is literal text
      elsif char == "`" && (close = source.index("`", i + 1))
        code = source[(i + 1)...close]
        [ html ? "#{open("code", html)}#{escape(code, true)}</code>" : code, close + 1 ]
      elsif char == "!" && (match = source.match(IMAGE, i))
        [ image(match[1], match[2], html), i + match[0].length ]
      elsif char == "[" && (match = source.match(LINK, i))
        [ link(match[1], match[2], html), i + match[0].length ]
      elsif char == "*" && (emphasis = emphasis(source, i, html))
        emphasis
      else
        [ escape(char, html), i + 1 ]
      end
    end
    private_class_method :inline_token

    # **strong** or *em* when a closing marker exists and the content does not start with a space.
    def self.emphasis(source, i, html)
      marker = source[i, 2] == "**" ? "**" : "*"
      start = i + marker.length
      close = closing_marker(source, start, marker)
      return if close.nil? || close == start || source[start].match?(/\s/)

      inner = inline(source[start...close], html)
      tag = marker == "**" ? "strong" : "em"
      [ html ? "#{open(tag, html)}#{inner}</#{tag}>" : inner, close + marker.length ]
    end
    private_class_method :emphasis

    # Index of the next unescaped +marker+ at or after +from+.
    def self.closing_marker(source, from, marker)
      i = from
      while i < source.length
        if source[i] == "\\"
          i += 2
        elsif source[i, marker.length] == marker
          return source[i + marker.length] == "*" && marker == "**" ? i + 1 : i # "***": the last two close
        else
          i += 1
        end
      end
      nil
    end
    private_class_method :closing_marker

    # An anchor for allowed URLs, otherwise just the (escaped) text. Plain text shows "text (url)".
    def self.link(label, url, html)
      text = inline(label, html)
      return text unless allowed_url?(url, LINK_URL)
      return (text == url ? text : "#{text} (#{url})") unless html

      %(<a href="#{escape(url, true)}"#{style("a", html)}>#{text}</a>)
    end
    private_class_method :link

    # An img tag for allowed URLs, otherwise just the escaped alt text.
    def self.image(alt, url, html)
      text = inline(alt, false)
      return escape(text, html) unless html && allowed_url?(url, IMAGE_URL)

      %(<img src="#{escape(url, true)}" alt="#{escape(text, true)}" loading="lazy"#{style("img", html)}>)
    end
    private_class_method :image

    def self.allowed_url?(url, pattern) = url.match?(pattern) && !url.match?(CONTROL_CHARS)
    private_class_method :allowed_url?

    def self.escape(text, html) = html ? ERB::Util.html_escape(text).to_str : text
    private_class_method :escape
  end
end
