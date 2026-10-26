require "test_helper"

# A host that mounts the engine under another name (`mount Shiplog::Engine => "/updates", as: :updates`)
# has no `shiplog` route proxy.
class CustomMountTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.routes.draw do
      root "home#show"
      get "news", to: "pages#news", as: :news
      mount Shiplog::Engine => "/updates", as: :updates
    end
    Shiplog::SwitcherHelper.reset_mount_name!
  end

  teardown do
    Rails.application.reload_routes!
    Shiplog::SwitcherHelper.reset_mount_name!
  end

  test "the engine's own pages link through the engine's routes" do
    get "/updates/roadmap"

    assert_response :ok
    assert_select "nav.shiplog-switcher a[href=?][aria-current=page]", "/updates/roadmap", text: "Roadmap"
    assert_select "nav.shiplog-switcher a[href=?]", "/updates/changelog", text: "Changelog"
  end

  test "shiplog_switcher on a host page finds the mounted proxy, for the links and the stylesheet" do
    get "/news"

    assert_response :ok
    assert_select "nav.shiplog-switcher a[href=?]", "/updates/roadmap"
    assert_select "nav.shiplog-switcher a[href=?]", "/updates/changelog"
    assert_select "link[rel=stylesheet][href^=?]", "/updates/shiplog/assets/"
  end

  test "the mount name is found once and remembered until the routes change" do
    assert_equal "updates", Shiplog::SwitcherHelper.mount_name
    assert_equal "updates", Shiplog::SwitcherHelper.mount_name
  end

  test "an engine that is not mounted raises a clear error" do
    Rails.application.routes.draw { get "news", to: "pages#news", as: :news }
    Shiplog::SwitcherHelper.reset_mount_name!

    error = assert_raises(ActionView::Template::Error) { get "/news" }
    assert_kind_of Shiplog::SwitcherHelper::NotMounted, error.cause
    assert_match(/mount Shiplog::Engine/, error.cause.message)
  end
end
