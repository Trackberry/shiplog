require "test_helper"

class Shiplog::EntryImageAttachmentsTest < ActiveJob::TestCase
  setup { @entry = shiplog_entries(:dark_mode_feature) }

  def file(type, name = "shot.#{type}") = { io: StringIO.new(image_bytes(type)), filename: name, content_type: Shiplog::ImageType::EXTENSIONS.key(type.to_s) }

  test "Active Storage is loaded in the dummy app, so screenshots are on" do
    assert Shiplog.active_storage?
    assert Shiplog.images?
    assert_respond_to @entry, :images
  end

  test "screenshots are off with config.images = false, whatever Active Storage says" do
    Shiplog.config.images = false
    assert Shiplog.active_storage?
    assert_not Shiplog.images?
  end

  test "the gate is closed when Active Storage is not loaded" do
    without_active_storage do
      assert_not Shiplog.images?
      assert_equal [], @entry.ordered_images
      assert_nil @entry.find_image(1)
      assert_equal [], @entry.image_etag_parts
    end
  end

  test "the gate looks for the Active Storage engine and the model macros" do
    assert_equal true, Shiplog.active_storage?
    ActiveRecord::Base.singleton_class.send(:alias_method, :__macro_backup, :has_many_attached)
    ActiveRecord::Base.singleton_class.send(:undef_method, :has_many_attached)
    assert_equal false, Shiplog.active_storage?
  ensure
    ActiveRecord::Base.singleton_class.send(:alias_method, :has_many_attached, :__macro_backup)
    ActiveRecord::Base.singleton_class.send(:remove_method, :__macro_backup)
    assert Shiplog.active_storage?
  end

  test "boot logs once why screenshots are off, only when Active Storage is the reason" do
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output = StringIO.new)

    Shiplog.log_images_status
    assert_empty output.string

    with_stub(Shiplog, :active_storage_loaded?, ->(*) { false }) { Shiplog.log_images_status }
    assert_match(/\[shiplog\] Screenshots are off: Active Storage is not loaded/, output.string)

    output.truncate(0)
    Shiplog.config.images = false
    with_stub(Shiplog, :active_storage_loaded?, ->(*) { false }) { Shiplog.log_images_status }
    assert_empty output.string
  ensure
    Rails.logger = original
  end

  test "an entry without images has none" do
    assert_empty @entry.ordered_images
    assert_equal [], @entry.image_order
    assert_equal({}, @entry.image_alts)
  end

  test "add_images attaches in order and records the order" do
    images = @entry.add_images([ file(:png), file(:jpg) ])
    assert_equal images.map(&:blob_id), @entry.reload.image_order
    assert_equal %w[image/png image/jpeg], @entry.ordered_images.map { |image| image.blob.content_type }

    more = @entry.add_images([ file(:gif) ])
    assert_equal images.map(&:blob_id) + more.map(&:blob_id), @entry.reload.ordered_images.map(&:blob_id)
  end

  test "attachments missing from image_order come last, and stale ids are ignored" do
    first, second = @entry.add_images([ file(:png), file(:gif) ])
    @entry.update_columns(image_order: [ 0, second.blob_id, "junk" ])
    assert_equal [ second.blob_id, first.blob_id ], @entry.reload.ordered_images.map(&:blob_id)
    @entry.update_columns(image_order: [])
    assert_equal [ first.blob_id, second.blob_id ], @entry.reload.ordered_images.map(&:blob_id)
  end

  test "alt text defaults to the title" do
    image, = @entry.add_images([ file(:png) ])
    assert_equal "Dark mode", @entry.image_alt(image)
    @entry.update_image_alt(image.blob_id, "The dark theme")
    assert_equal "The dark theme", @entry.reload.image_alt(image)
    assert_equal({ image.blob_id.to_s => "The dark theme" }, @entry.image_alts)
  end

  test "remove_image deletes the attachment, its order entry and alt text, and purges the blob later" do
    first, second = @entry.add_images([ file(:png), file(:gif) ])
    @entry.update_image_alt(first.blob_id, "Alt")

    assert_enqueued_with(job: ActiveStorage::PurgeJob) { @entry.remove_image(first.blob_id) }

    @entry.reload
    assert_equal [ second.blob_id ], @entry.ordered_images.map(&:blob_id)
    assert_equal [ second.blob_id ], @entry.image_order
    assert_empty @entry.image_alts
    assert_not @entry.remove_image(first.blob_id)
  end

  test "move_image swaps neighbours and ignores moves past the ends" do
    a, b = @entry.add_images([ file(:png), file(:gif) ]).map(&:blob_id)
    assert_not @entry.move_image(a, :up)
    assert_not @entry.move_image(b, :down)
    assert @entry.move_image(b, :up)
    assert_equal [ b, a ], @entry.reload.ordered_images.map(&:blob_id)
  end

  test "changing the images bumps updated_at" do
    travel_to 1.hour.from_now do
      assert_changes -> { @entry.reload.updated_at } do
        @entry.add_images([ file(:png) ])
      end
    end
  end
end
