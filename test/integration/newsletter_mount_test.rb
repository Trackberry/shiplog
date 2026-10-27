require "test_helper"

# The newsletter's routes under a host that constrains the engine's mount to its own paths (Trackberry mounts
# the engine at "/" and lets only the roadmap, the changelog and /shiplog/ through), and under a mount prefix.
class NewsletterMountTest < ActionDispatch::IntegrationTest
  setup do
    enable_newsletter!
    @subscriber = Shiplog::NewsletterSubscriber.create!(email: "ana@example.com", locale: "en", confirmed_at: Time.current)
    Shiplog::SwitcherHelper.reset_mount_name!
  end

  teardown do
    Rails.application.reload_routes!
    Shiplog::SwitcherHelper.reset_mount_name!
  end

  test "the newsletter pages pass a constraint that only lets roadmap, changelog and /shiplog/ paths through" do
    Rails.application.routes.draw do
      root "home#show"
      constraints ->(request) { request.path.match?(%r{\A/(roadmap|changelog|shiplog/)}) } do
        mount Shiplog::Engine => "/"
      end
    end

    get "/shiplog/newsletter/subscription"
    assert_response :ok
    get "/shiplog/newsletter/preferences/#{@subscriber.token}"
    assert_response :ok
    post "/shiplog/newsletter/unsubscribe/#{Shiplog::Newsletter::Tokens.unsubscribe("ana@example.com")}"
    assert_response :ok
    assert @subscriber.reload.unsubscribed?
    get "/changelog"
    assert_select "form[action=?]", "/shiplog/newsletter/subscription"
  end

  test "the links in emails carry the mount prefix" do
    Rails.application.routes.draw do
      root "home#show"
      mount Shiplog::Engine => "/updates", as: :updates
    end

    assert_equal "https://example.com/updates/shiplog/newsletter/preferences/#{@subscriber.token}", Shiplog::Newsletter.preferences_url(@subscriber)
    assert_match %r{\Ahttps://example\.com/updates/shiplog/newsletter/unsubscribe/}, Shiplog::Newsletter.unsubscribe_url("ana@example.com")
    assert_equal "https://example.com/updates/changelog", Shiplog::Newsletter.changelog_url
    get "/updates/changelog"
    assert_select "form[action=?]", "/updates/shiplog/newsletter/subscription"
    get "/updates/shiplog/newsletter/subscription"
    assert_response :ok
  end
end
