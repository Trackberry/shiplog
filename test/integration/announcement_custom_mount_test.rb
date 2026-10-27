require "test_helper"

# A host that mounts the engine below "/updates": links built outside a request (drafting, exports, the approval
# hook) must carry the mount prefix, and the pages answer under it.
class AnnouncementCustomMountTest < ActionDispatch::IntegrationTest
  setup do
    Rails.application.routes.draw do
      root "home#show"
      mount Shiplog::Engine => "/updates", as: :updates
      mount Shiplog::Admin::Engine => "/admin/shiplog"
    end
    Shiplog::SwitcherHelper.reset_mount_name!
  end

  teardown do
    Rails.application.reload_routes!
    Shiplog::SwitcherHelper.reset_mount_name!
  end

  test "PublicLinks finds the mount path" do
    assert_equal "/updates", Shiplog::PublicLinks.mount_path
    assert_equal "/updates/changelog", Shiplog::PublicLinks.changelog_url
    assert_equal "/updates/changelog/dark-mode", Shiplog::PublicLinks.entry_url(shiplog_entries(:dark_mode_feature))
  end

  test "PublicLinks adds canonical_url in front of the mount path" do
    Shiplog.config.canonical_url = "https://example.com"

    assert_equal "https://example.com/updates/changelog/dark-mode", Shiplog::PublicLinks.entry_url(shiplog_entries(:dark_mode_feature))
  end

  test "an announcement's skeleton and public_url use the mount prefix" do
    announcement = Shiplog::Announcements.draft(month: Date.new(2026, 10, 1))

    assert_includes announcement.body, "[Dark mode](/updates/changelog/dark-mode)"
    assert_equal "/updates/changelog/2026-10", announcement.public_url
  end

  test "the announcement page and the month link answer under the mount" do
    announcement = Shiplog::Announcements.draft(month: Date.new(2026, 10, 1))
    announcement.approve!(by: "ed@example.com")

    get "/updates/changelog/2026-10"
    assert_response :ok
    assert_select "article.shiplog-announcement"

    get "/updates/changelog"
    assert_select "a[href=?]", "/updates/changelog/2026-10", text: "Read the October 2026 summary"
  end

  test "PublicLinks has an empty mount path when the engine is not mounted at all" do
    Rails.application.routes.draw { root "home#show" }

    assert_equal "", Shiplog::PublicLinks.mount_path
  end

  test "an optional scope segment around the mount is left out of the links" do
    Rails.application.routes.draw do
      root "home#show"
      scope "(:locale)" do
        mount Shiplog::Engine => "/"
      end
    end

    assert_equal "", Shiplog::PublicLinks.mount_path
    assert_equal "/changelog/dark-mode", Shiplog::PublicLinks.entry_url(shiplog_entries(:dark_mode_feature))
  end

  test "a required scope segment falls back to the root" do
    Rails.application.routes.draw do
      root "home#show"
      scope ":tenant" do
        mount Shiplog::Engine => "/"
      end
    end

    assert_equal "", Shiplog::PublicLinks.mount_path
  end

  test "links still build outside a request when the mount sits under a required scope segment" do
    Rails.application.routes.draw do
      root "home#show"
      scope ":tenant" do
        mount Shiplog::Engine => "/"
      end
    end

    assert_equal "/changelog/dark-mode", Shiplog::PublicLinks.entry_url(shiplog_entries(:dark_mode_feature))
  end
end
