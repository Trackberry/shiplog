require "test_helper"

# Hosts copy engine partials to override them. A copy from an older release must keep rendering, so a partial's
# locals may only grow optional ones the engine's own templates don't need to pass.
class Shiplog::ViewOverrideCompatTest < ActionDispatch::IntegrationTest
  OVERRIDES = Rails.root.join("../fixtures/files/views/v0_2_0").freeze

  setup do
    @original_paths = Shiplog::ChangelogsController.view_paths
    Shiplog::ChangelogsController.prepend_view_path(OVERRIDES.to_s)
    billing = Shiplog::Area.create!(name: "Billing")
    shiplog_entries(:dark_mode_feature).update!(area: billing)
  end

  teardown { Shiplog::ChangelogsController.view_paths = @original_paths }

  test "the v0.2.0 _search partial (strict locals: query, count) still renders, with or without an area" do
    get "/changelog"
    assert_response :ok
    assert_select "form[role=search]"

    get "/changelog", params: { area: "billing", q: "dark" }
    assert_response :ok
    assert_select "form[role=search]"
    assert_select "a.shiplog-search__clear[href=?]", "/changelog", { text: "Clear search" }, "the old partial does not carry the area, which is accepted"
  end
end
