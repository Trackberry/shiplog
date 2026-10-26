require "test_helper"

# A host that loads Active Storage (rails/all) but never installed its tables: every page still answers 200 and
# no query touches the missing tables.
class Shiplog::MissingActiveStorageTablesTest < ActionDispatch::IntegrationTest
  setup do
    @entry = shiplog_entries(:dark_mode_feature)
    @entry.add_images([ { io: StringIO.new(image_bytes(:png)), filename: "first.png", content_type: "image/png" } ])
    Shiplog.reset_images_checks!
  end

  def connection = ActiveRecord::Base.connection_pool.lease_connection

  def without_tables(&block)
    exists = connection.method(:data_source_exists?)
    with_stub(connection, :data_source_exists?, ->(name) { name.to_s.start_with?("active_storage") ? false : exists.call(name) }, &block)
  end

  test "the gate is closed when the tables are missing, though Active Storage is loaded" do
    without_tables do
      assert Shiplog.active_storage_loaded?
      assert_not Shiplog.active_storage?
      assert_not Shiplog.images?
      assert_equal [], @entry.ordered_images
      assert_nil @entry.find_image(1)
      assert_equal [], @entry.image_etag_parts
    end
  end

  test "the list, the permalink, the feed and the admin edit page answer 200 and query no Active Storage table" do
    without_tables do
      statements = sql_statements do
        [ "/changelog", "/changelog/dark-mode", "/changelog.atom", "/admin/shiplog/entries/#{@entry.id}/edit" ].each do |path|
          get path
          assert_response :ok, path
        end
        assert_select ".shiplog-admin-images", 0
      end
      assert_empty statements.grep(/active_storage_/)
    end
  end

  test "the admin image actions are 404 while the tables are missing" do
    without_tables do
      post "/admin/shiplog/entries/#{@entry.id}/images", params: { images: [ image_upload(:png) ] }
      assert_response :not_found
    end
  end

  test "the images show again once the tables exist" do
    get "/changelog/dark-mode"
    assert_select "img.shiplog-entry__image", 1
  end

  test "the check runs once per process, not per request" do
    checked = []
    exists = connection.method(:data_source_exists?)
    with_stub(connection, :data_source_exists?, ->(name) { checked << name.to_s; exists.call(name) }) do
      3.times { get "/changelog" }
      assert Shiplog.active_storage?
    end
    assert_equal %w[active_storage_attachments active_storage_blobs], checked.uniq.grep(/active_storage/)
    assert_equal 2, checked.size
  end

  test "a missing table is logged once, with the reason" do
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output = StringIO.new)
    without_tables do
      3.times { Shiplog.active_storage? }
      Shiplog.log_images_status
    end
    assert_equal 1, output.string.scan("[shiplog] Screenshots are off: Active Storage's tables are missing").size
    assert_match(/active_storage:install/, output.string)
  ensure
    Rails.logger = original
  end

  test "a database that can't be reached is not yet known: off for now, asked again later, nothing remembered" do
    with_stub(connection, :data_source_exists?, ->(_name) { raise ActiveRecord::ConnectionNotEstablished }) do
      assert_not Shiplog.active_storage?
      assert_not Shiplog.images?
    end
    assert Shiplog.active_storage?
  end

  test "images are not logged as off when config.images is false" do
    Shiplog.config.images = false
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output = StringIO.new)
    without_tables { Shiplog.log_images_status }
    assert_empty output.string
  ensure
    Rails.logger = original
  end
end
