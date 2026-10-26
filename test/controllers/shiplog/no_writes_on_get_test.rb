require "test_helper"

# GETs may be served by a read replica: the public pages never write.
class Shiplog::NoWritesOnGetTest < ActionDispatch::IntegrationTest
  setup do
    @slugless = shiplog_entries(:dark_mode_feature)
    @slugless.update_columns(slug: nil)
    now = Time.current
    Shiplog::Entry.insert_all!([ { kind: "change", status: "approved", subject_type: "Shiplog::Issue", subject_id: 30_000, title: "Older entry",
      body: "Body", slug: "older-entry", released_on: Date.new(2026, 9, 1), approved_at: now, created_at: now, updated_at: now } ])
  end

  def writes = ->(statements) { statements.grep(/\A\s*(UPDATE|INSERT|DELETE)\b/i) }

  test "the changelog list issues no UPDATE and shows an entry without a slug unlinked" do
    statements = sql_statements { get "/changelog" }
    assert_response :ok
    assert_empty writes.(statements)
    assert_select "h3", text: "Dark mode"
    assert_select "h3 a", text: "Dark mode", count: 0
    assert_select "h3 a", text: "Older entry"
    assert_nil @slugless.reload.slug
  end

  test "the feed issues no UPDATE and leaves the slugless entry out" do
    statements = sql_statements { get "/changelog.atom" }
    assert_response :ok
    assert_empty writes.(statements)
    assert_no_match(/Dark mode/, response.body)
    assert_match(/Older entry/, response.body)
  end

  test "a permalink page issues no UPDATE and shows a slugless neighbour unlinked" do
    statements = sql_statements { get "/changelog/older-entry" }
    assert_response :ok
    assert_empty writes.(statements)
    assert_select "nav.shiplog-permalink__nav", text: /Dark mode/
    assert_select "nav.shiplog-permalink__nav a", count: 0
    assert_nil @slugless.reload.slug
  end

  test "a slugless entry has no permalink page" do
    get "/changelog/dark-mode"
    assert_response :not_found
  end
end
