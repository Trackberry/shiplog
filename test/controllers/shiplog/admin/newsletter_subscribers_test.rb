require "test_helper"

class Shiplog::Admin::NewsletterSubscribersTest < ActionDispatch::IntegrationTest
  PATH = "/admin/shiplog/newsletter".freeze

  setup do
    enable_newsletter!
    Shiplog.config.locales = [ :es ]
    @ana = Shiplog::NewsletterSubscriber.create!(email: "ana@example.com", locale: "en", source: "/changelog", confirmed_at: Time.current)
    @bob = Shiplog::NewsletterSubscriber.create!(email: "bob@example.com", locale: "es")
    @gone = Shiplog::NewsletterSubscriber.create!(email: "gone@example.com", locale: "es", confirmed_at: Time.current, unsubscribed_at: Time.current)
  end

  test "the page shows the counts per locale and status and the list" do
    get PATH

    assert_response :ok
    assert_select "h1", text: "Newsletter"
    assert_select "table.shiplog-admin-counts" do
      assert_select "thead th", text: "Confirmed"
      assert_select "tr", text: /en\s+0\s+1\s+0/
      assert_select "tr", text: /es\s+1\s+0\s+1/
      assert_select "tr", text: /Total\s+1\s+1\s+1/
    end
    assert_select "#shiplog-subscriber-#{@ana.id}" do
      assert_select "td", text: "ana@example.com"
      assert_select "td", text: "Confirmed"
      assert_select "td", text: "/changelog"
      assert_select "form[action=?] input[name=_method][value=delete]", "#{PATH}/#{@ana.id}"
    end
    assert_select "#shiplog-subscriber-#{@bob.id} td", text: "Pending"
    assert_select "#shiplog-subscriber-#{@gone.id} td", text: "Unsubscribed"
    assert_select "a[href=?]", "#{PATH}.csv", text: "Download CSV"
  end

  test "the search filters the list and the export" do
    get PATH, params: { q: "BO" }

    assert_select "#shiplog-subscriber-#{@bob.id}"
    assert_select "#shiplog-subscriber-#{@ana.id}", count: 0
    assert_select "a[href=?]", "#{PATH}.csv?q=BO"
    assert_select "a[href=?]", PATH, text: "Clear"

    get PATH, params: { q: "nobody" }
    assert_select "p.shiplog-admin__empty", text: /No subscriber matches “nobody”/
  end

  test "the list is paginated" do
    Shiplog::Admin::NewsletterSubscribersController::PER_PAGE.times { |i| Shiplog::NewsletterSubscriber.create!(email: "p#{i}@example.com", locale: "en") }

    get PATH
    assert_select "tbody tr[id^=shiplog-subscriber-]", 100
    assert_select "a.shiplog-admin-pagination__next[href=?]", "#{PATH}?page=2"

    get PATH, params: { page: 2 }
    assert_select "tbody tr[id^=shiplog-subscriber-]", 3
    assert_select "a.shiplog-admin-pagination__prev[href=?]", PATH
  end

  test "removing a subscriber deletes the row and keeps the search" do
    delete "#{PATH}/#{@bob.id}", params: { q: "bo" }

    assert_redirected_to "#{PATH}?q=bo"
    assert_nil Shiplog::NewsletterSubscriber.find_by(id: @bob.id)
    follow_redirect!
    assert_select ".shiplog-admin__flash--notice", text: "bob@example.com removed."
  end

  test "the CSV export lists the subscribers with formulas neutralised" do
    Shiplog::NewsletterSubscriber.create!(email: "=1+1@example.com", locale: "en", source: "/changelog")

    get "#{PATH}.csv"

    assert_response :ok
    assert_equal "text/csv; charset=utf-8", response.headers["Content-Type"]
    assert_match(/\Aattachment; filename="shiplog-newsletter-subscribers-\d{4}-\d{2}-\d{2}\.csv"/, response.headers["Content-Disposition"])
    lines = response.body.lines(chomp: true)
    assert_equal %("email","locale","status","source","subscribed_at","confirmed_at","unsubscribed_at"), lines.first
    assert_equal 5, lines.size
    assert lines.any? { |line| line.start_with?(%("'=1+1@example.com","en","pending","/changelog",)) }
    assert lines.any? { |line| line.start_with?(%("ana@example.com","en","confirmed","/changelog",)) }

    get "#{PATH}.csv", params: { q: "ana" }
    assert_equal 2, response.body.lines.size
  end

  test "the page is not found while the newsletter is off" do
    Shiplog.config.newsletter = false

    get PATH
    assert_response :not_found
    get "#{PATH}.csv"
    assert_response :not_found
    delete "#{PATH}/#{@bob.id}"
    assert_response :not_found
    assert Shiplog::NewsletterSubscriber.exists?(@bob.id)
  end

  test "the page needs an authorised admin" do
    Shiplog.config.authorize_admin = ->(_controller) { false }

    get "#{PATH}.csv"
    assert_response :forbidden
    assert_not_includes response.body, "ana@example.com"
  end
end
