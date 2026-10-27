require "test_helper"

class Shiplog::AnnouncementRewriteTest < ActiveJob::TestCase
  setup do
    @entry = Shiplog::Announcements.draft(month: Date.new(2026, 10, 1))
    @prompts = []
  end

  def reply(title: "What shipped in October", body: "Intro.\n\n## Highlights\n\n### Dark mode\n\nTry it. [Read more](/changelog/dark-mode)", **extra)
    JSON.generate({ title:, body: }.merge(extra))
  end

  def rewrite(text = reply)
    Shiplog.config.rewriter = lambda do |prompt|
      @prompts << prompt
      text
    end
    Shiplog::Rewriter.new(@entry).call
    @entry.reload
  end

  test "the rewriter receives the announcement prompt with the month, the entries and their pages" do
    rewrite

    prompt = @prompts.first
    assert_includes prompt, "October 2026"
    assert_includes prompt, "Dark mode"
    assert_includes prompt, "Switch to a dark theme."
    assert_includes prompt, "page: /changelog/dark-mode"
    assert_includes prompt, "<source>"
    assert_includes prompt, "</source>"
    assert_includes prompt, "Markdown"
  end

  test "the prompt lists small changes without a page" do
    Shiplog.config.repositories = [ "Trackberry/trackberry" ]
    Shiplog::PullRequest.create!(repository: shiplog_repositories(:app), node_id: "PR_loose", number: 200, title: "Loose fix", state: "merged",
      merged_at: Time.zone.local(2026, 10, 12, 10), author_login: "edouard")
    rewrite

    assert_includes @prompts.first, "Small changes without a page:"
    assert_includes @prompts.first, "- Loose fix"
    assert_not_includes @prompts.first, "Validate CSV headers" # linked to a public issue tree
  end

  test "it stores the title and the Markdown body" do
    rewrite

    assert_equal "What shipped in October", @entry.title
    assert_includes @entry.body, "## Highlights"
    assert_includes @entry.body, "[Read more](/changelog/dark-mode)"
    assert @entry.rewritten_at
    assert_nil @entry.rewrite_error
    assert @entry.draft?
  end

  test "it keeps a body longer than 2000 characters, up to the announcement limit" do
    long = "Sentence number one is here. " * 100
    assert_operator long.length, :>, Shiplog::Rewriter::MAX_BODY_CHARS

    rewrite(reply(body: long))
    assert_equal long.strip, @entry.body

    rewrite(reply(body: "word " * 5_000))
    assert_operator @entry.body.length, :<=, Shiplog::Rewriter::MAX_ANNOUNCEMENT_BODY_CHARS
    assert_operator @entry.body.length, :>, Shiplog::Rewriter::MAX_BODY_CHARS
    assert @entry.body.end_with?("…")
  end

  test "an announcement is never given an area" do
    rewrite(reply(area: "Billing"))

    assert_nil @entry.area_id
    assert_equal 0, Shiplog::Area.count
  end

  test "an announcement is never discarded because the reply says it is not customer-facing" do
    rewrite(reply(customer_facing: false))

    assert @entry.draft?
    assert_nil @entry.discard_reason
    assert_equal "What shipped in October", @entry.title
  end

  test "source_digest is the period's content digest, and the draft is flagged once an entry of the month changes" do
    rewrite

    assert_equal @entry.subject.content_digest, @entry.source_digest
    assert_not @entry.source_changed?

    shiplog_entries(:dark_mode_feature).update!(body: "Now with a switch in the menu.")

    assert @entry.reload.source_changed?
  end

  test "the digest ignores entries of other months" do
    rewrite
    other = Shiplog::Entry.create!(kind: "change", status: "approved", released_on: Date.new(2026, 9, 3), approved_at: Time.current,
      title: "September", slug: "september", subject: Shiplog::Commit.create!(repository: shiplog_repositories(:app),
        sha: SecureRandom.hex(20), message: "m", committed_at: Time.current, url: "https://example.com/c"))
    other.update!(body: "Changed")

    assert_not @entry.reload.source_changed?
  end

  test "config.prompt_builder receives kind announcement and the context as data" do
    received = nil
    Shiplog.config.prompt_builder = lambda do |**arguments|
      received = arguments
      "CUSTOM PROMPT"
    end

    rewrite

    assert_equal [ "CUSTOM PROMPT" ], @prompts
    assert_equal "announcement", received[:kind]
    context = received[:context]
    assert_kind_of Hash, context
    assert_equal "October 2026", context[:month]
    assert_equal [ "Dark mode" ], context[:entries].map { |entry| entry[:title] }
    assert_equal "/changelog/dark-mode", context[:entries].first[:url]
    assert_equal "feature", context[:entries].first[:kind]
    assert_kind_of Array, context[:skipped]
  end

  test "without a rewriter the draft is the month's fresh skeleton, without an error" do
    Shiplog::Rewriter.new(@entry).call
    @entry.reload

    assert_equal "October 2026", @entry.title
    assert_equal @entry.subject.body, @entry.body
    assert_nil @entry.rewrite_error
    assert @entry.rewritten_at
    assert_equal @entry.subject.content_digest, @entry.source_digest
  end

  test "regenerating without a rewriter rebuilds the skeleton from the month's current entries" do
    Shiplog::Rewriter.new(@entry).call
    @entry.update!(body: "Hand-written text")
    shiplog_entries(:dark_mode_feature).update!(title: "Dark mode everywhere")

    Shiplog::Rewriter.new(@entry).call(force: true)

    assert_includes @entry.reload.body, "[Dark mode everywhere](/changelog/dark-mode)"
    assert_not_includes @entry.body, "Hand-written"
  end

  test "regenerating an approved announcement without a rewriter returns it to draft" do
    @entry.approve!(by: "ed@example.com")

    Shiplog::Rewriter.new(@entry).call
    assert @entry.reload.approved?

    Shiplog::Rewriter.new(@entry).call(force: true)
    @entry.reload
    assert @entry.draft?
    assert_nil @entry.approved_at
    assert_nil @entry.rewrite_error
  end

  test "a prompt_builder returning nil falls back to the built-in prompt" do
    Shiplog.config.prompt_builder = ->(**) { nil }

    rewrite

    assert_includes @prompts.first, "<source>"
    assert_includes @prompts.first, "October 2026"
    assert_equal "What shipped in October", @entry.title
  end

  test "an unparseable reply keeps the skeleton and records the parse error" do
    skeleton = @entry.body

    rewrite("no json here")

    assert_equal skeleton, @entry.body
    assert_equal Shiplog::Rewriter::PARSE_ERROR, @entry.rewrite_error
  end

  test "a forced rewrite of an approved announcement returns it to draft" do
    @entry.approve!(by: "ed@example.com")
    Shiplog.config.rewriter = ->(_prompt) { reply }

    Shiplog::Rewriter.new(@entry).call(force: true)

    assert @entry.reload.draft?
    assert_nil @entry.approved_at
  end

  test "RewriteEntryJob rewrites the drafted announcement" do
    Shiplog.config.rewriter = ->(_prompt) { reply }

    Shiplog::RewriteEntryJob.perform_now(@entry.id)

    assert_equal "What shipped in October", @entry.reload.title
  end

  test "the translation of an announcement keeps a long Markdown body and the prompt mentions Markdown" do
    Shiplog.config.locales = [ :es ]
    long = "## Destacados\n\n" + ("Una frase de ejemplo con [enlace](/changelog/dark-mode). " * 80)
    assert_operator long.length, :>, Shiplog::Rewriter::MAX_BODY_CHARS
    @entry.update!(title: "What shipped", body: "## Highlights\n\n" + ("An example sentence with a [link](/changelog/dark-mode). " * 80))
    @entry.approve!(by: "ed@example.com")
    Shiplog.config.rewriter = lambda do |prompt|
      @prompts << prompt
      JSON.generate(title: "Novedades", body: long)
    end

    Shiplog::Translator.new(@entry, :es).call

    translation = @entry.translations.find_by!(locale: "es")
    assert_equal long.strip, translation.body
    assert_includes @prompts.first, "Markdown"
    assert_includes @prompts.first, "Spanish"
  end

  test "a translation body is cut at the announcement limit, not at 2000 characters" do
    Shiplog.config.locales = [ :es ]
    @entry.approve!(by: "ed@example.com")
    Shiplog.config.rewriter = ->(_prompt) { JSON.generate(title: "T", body: "palabra " * 3_000) }

    Shiplog::Translator.new(@entry, :es).call

    length = @entry.translations.find_by!(locale: "es").body.length
    assert_operator length, :>, Shiplog::Rewriter::MAX_BODY_CHARS
    assert_operator length, :<=, Shiplog::Rewriter::MAX_ANNOUNCEMENT_BODY_CHARS
  end
end
