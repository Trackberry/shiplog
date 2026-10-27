require "test_helper"

class Shiplog::MarkdownTest < ActiveSupport::TestCase
  def html(text, **options) = Shiplog::Markdown.to_html(text, **options)

  def text(source) = Shiplog::Markdown.to_text(source)

  test "headings, with the offset applied and clamped" do
    assert_equal "<h1>Title</h1>\n<h3>Sub</h3>", html("# Title\n### Sub")
    assert_equal "<h2>Title</h2>", html("# Title", heading_offset: 1)
    assert_equal "<h6>Deep</h6>", html("###### Deep", heading_offset: 2)
    assert_equal "<h1>Up</h1>", html("# Up", heading_offset: -3)
  end

  test "paragraphs join their lines with soft breaks" do
    assert_equal "<p>one\ntwo</p>\n<p>three</p>", html("one\ntwo\n\nthree")
  end

  test "unordered lists, any marker, indented items continue the list" do
    assert_equal "<ul>\n<li>a</li>\n<li>b</li>\n<li>c</li>\n</ul>", html("- a\n* b\n  + c")
  end

  test "ordered lists" do
    assert_equal "<ol>\n<li>a</li>\n<li>b</li>\n</ol>", html("1. a\n2) b")
  end

  test "a list ends at a blank line followed by text, or at a heading" do
    assert_equal "<ul>\n<li>a</li>\n</ul>\n<p>text</p>", html("- a\n\ntext")
    assert_equal "<ul>\n<li>a</li>\n<li>b</li>\n</ul>", html("- a\n\n- b")
    assert_equal "<ul>\n<li>a</li>\n</ul>\n<h2>H</h2>", html("- a\n## H")
  end

  test "blockquotes and horizontal rules" do
    assert_equal "<blockquote><p>quoted\nmore</p></blockquote>", html("> quoted\n> more")
    assert_equal "<hr>\n<hr>\n<hr>", html("---\n\n***\n\n___")
    assert_equal "<ul>\n<li>a</li>\n</ul>", html("- a")
  end

  test "fenced code is plain text" do
    assert_equal "<p>```\ncode\n```</p>", html("```\ncode\n```")
  end

  test "inline emphasis, code and underscores" do
    assert_equal "<p><strong>b</strong> <em>i</em> <code>c *x*</code> snake_case_word</p>", html("**b** *i* `c *x*` snake_case_word")
    assert_equal "<p><strong>a <em>b</em></strong></p>", html("**a *b***")
    assert_equal "<p>2 * 3 * 4</p>", html("2 * 3 * 4")
  end

  test "links and images" do
    assert_equal %(<p><a href="https://a.com/x?y=1&amp;z=2">go</a></p>), html("[go](https://a.com/x?y=1&z=2)")
    assert_equal %(<p><a href="/p">p</a> <a href="#top">t</a> <a href="mailto:a@b.co">m</a></p>), html("[p](/p) [t](#top) [m](mailto:a@b.co)")
    assert_equal %(<p><img src="https://a.com/i.png" alt="pic" loading="lazy"></p>), html("![pic](https://a.com/i.png)")
    assert_equal %(<p><a href="https://a.com/a_(b)">x</a></p>), html("[x](https://a.com/a_(b))")
  end

  test "backslash escapes" do
    assert_equal "<p>*not em* [not](link) _ # ! - `x` \\</p>", html('\*not em\* \[not\]\(link\) \_ \# \! \- \`x\` \\\\')
  end

  test "blank input" do
    [ nil, "", "  \n \n" ].each do |blank|
      assert_equal "", html(blank)
      assert_predicate html(blank), :html_safe?
      assert_equal "", text(blank)
    end
  end

  test "to_text" do
    source = "# Title\n\nSome **bold** and *em* with `code`.\n\n- a\n- [site](https://a.com)\n\n1. one\n2. [https://b.com](https://b.com)\n\n> quote\n\n---\n\n![alt text](/i.png) [x](javascript:alert(1)) <b>"
    expected = "Title\n\nSome bold and em with code.\n\n- a\n- site (https://a.com)\n\n1. one\n2. https://b.com\n\nquote\n\nalt text x <b>"
    assert_equal expected, text(source)
  end

  test "raw html is escaped" do
    assert_equal "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>", html("<script>alert(1)</script>")
    assert_equal "<p>&lt;img src=x onerror=y&gt;</p>", html("<img src=x onerror=y>")
    assert_equal "<h1>&lt;b&gt;</h1>", html("# <b>")
  end

  test "unsafe link urls render only the escaped text" do
    [ "[x](javascript:alert(1))", "[x](JaVaScRiPt:alert(1))", "[x]( javascript:alert(1))", "[x](//evil.com)",
     "[x](/\\evil.com)", "[x](data:text/html,hi)", "[x](vbscript:y)", "[x](\tjavascript:y)" ].each do |source|
      result = html(source)
      assert_no_match(/<a /, result, source)
      assert_includes result, "x", source
    end
    assert_equal "<p>x</p>", html("[x](javascript:alert(1))")
    assert_equal "<p>&lt;i&gt;</p>", html("[<i>](javascript:1)")
  end

  test "attribute values cannot be broken out of" do
    result = html('[x](https://a.com" onmouseover="y)')
    assert_equal %(<p><a href="https://a.com&quot; onmouseover=&quot;y">x</a></p>), result
    result = html('![a" onerror="y](https://a.com/i.png" onerror="z)')
    assert_no_match(/ onerror="/, result)
  end

  test "unsafe image urls render nothing but the escaped alt text" do
    assert_equal "<p>x</p>", html("![x](data:image/png;base64,AAA)")
    assert_equal "<p>x</p>", html("![x](javascript:1)")
    assert_equal "<p>&lt;i&gt;</p>", html("![<i>](//evil.com/a.png)")
    assert_no_match(/<img/, html("![x](mailto:a@b.co)"))
  end

  test "the result is html_safe" do
    assert_predicate html("# a\n\n<script>"), :html_safe?
    assert_kind_of ActiveSupport::SafeBuffer, html("text")
  end
end
