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

  FakeAttachment = Struct.new(:id, :blob_id) do
    def purge_later = true
  end

  # An entry whose blobs have UUID primary keys, as in a host that uses uuid ids (the dummy app uses bigint).
  def with_uuid_blobs(ids)
    attachments = ids.each_with_index.map { |blob_id, index| FakeAttachment.new(index + 1, blob_id) }
    images = Struct.new(:attachments).new(attachments)
    with_stub(@entry, :images, ->(*) { images }) { yield attachments }
  end

  UUIDS = %w[0b0d6d3a-1111-4c1b-8a6a-000000000001 5f8a1c2e-2222-4c1b-8a6a-000000000002 c9e4f7a0-3333-4c1b-8a6a-000000000003].freeze

  test "blob ids are compared as strings, so UUID ids order, find, move and get alt texts" do
    with_uuid_blobs(UUIDS) do
      @entry.update_columns(image_order: [ UUIDS[2], UUIDS[0] ])
      assert_equal [ UUIDS[2], UUIDS[0], UUIDS[1] ], @entry.ordered_images.map(&:blob_id)
      assert_equal UUIDS[1], @entry.find_image(UUIDS[1]).blob_id
      assert_nil @entry.find_image("not-a-uuid")

      assert @entry.move_image(UUIDS[1], :up)
      assert_equal [ UUIDS[2], UUIDS[1], UUIDS[0] ], @entry.image_order
      assert_not @entry.move_image(UUIDS[2], :up)
      assert_not @entry.move_image("not-a-uuid", :up)

      assert @entry.update_image_alt(UUIDS[1], "Second")
      assert_equal({ UUIDS[1] => "Second" }, @entry.image_alts)
      assert_equal "Second", @entry.image_alt(@entry.find_image(UUIDS[1]))

      assert @entry.remove_image(UUIDS[2])
      assert_equal [ UUIDS[1], UUIDS[0] ], @entry.image_order
    end
  end

  test "ids kept in image_order as strings or integers match the same blob" do
    first, second = @entry.add_images([ file(:png), file(:gif) ])
    @entry.update_columns(image_order: [ second.blob_id.to_s, first.blob_id ])
    assert_equal [ second.blob_id, first.blob_id ], @entry.reload.ordered_images.map(&:blob_id)
    assert @entry.find_image(first.blob_id.to_s)
    assert @entry.find_image(first.blob_id)
  end

  test "a non-Hash image_alts is treated as empty" do
    image, = @entry.add_images([ file(:png) ])
    [ [ "x" ], "text", 3, [ [ image.blob_id.to_s, "pair" ] ] ].each do |junk|
      @entry.update_columns(image_alts: junk)
      @entry.reload
      assert_equal "Dark mode", @entry.image_alt(image), junk.inspect
      assert @entry.update_image_alt(image.blob_id, "Fixed")
      assert_equal({ image.blob_id.to_s => "Fixed" }, @entry.reload.image_alts)
      assert @entry.update_image_alt(image.blob_id, "")
    end
    @entry.update_columns(image_alts: [ "x" ])
    assert @entry.reload.remove_image(image.blob_id)
    assert_equal({}, @entry.image_alts)
  end

  test "files are uploaded before the row lock is taken, and only attached under it" do
    log = []
    lock = @entry.method(:with_lock)
    with_stub(@entry, :with_lock, ->(*args, &block) { log << :lock; lock.call(*args, &block) }) do
      tracking_uploads(log) { @entry.add_images([ file(:png), file(:gif) ]) }
    end

    assert_equal [ :upload, :upload, :lock ], log
    assert_equal 2, @entry.reload.ordered_images.size
  end

  test "a failure in the third of four uploads purges the first two blobs and attaches nothing" do
    blobs = nil
    assert_no_difference -> { ActiveStorage::Blob.count } do
      error = assert_raises(IOError) do
        tracking_uploads(fail_at: 3) do |uploaded|
          blobs = uploaded
          @entry.add_images([ file(:png), file(:gif), file(:jpg), file(:webp) ])
        end
      end
      assert_equal "storage down", error.message
    end

    assert_equal 2, blobs.size
    blobs.each { |blob| assert_not blob_stored?(blob) }
    assert_equal 0, @entry.reload.images.count
    assert_empty @entry.image_order
  end

  test "a failure while attaching purges every uploaded blob, files included" do
    blobs = nil
    assert_no_difference -> { ActiveStorage::Blob.count } do
      with_stub(@entry, :update!, ->(*) { raise ActiveRecord::StatementInvalid, "deadlock" }) do
        assert_raises(ActiveRecord::StatementInvalid) do
          tracking_uploads do |uploaded|
            blobs = uploaded
            @entry.add_images([ file(:png), file(:gif) ])
          end
        end
      end
    end

    assert_equal 2, blobs.size
    blobs.each { |blob| assert_not blob_stored?(blob) }
    assert_equal 0, @entry.reload.images.count
  end

  test "when the condition given for under the lock no longer holds, nothing is attached and the blobs are purged" do
    blobs = nil
    attached = tracking_uploads do |uploaded|
      blobs = uploaded
      @entry.add_images([ file(:png) ]) { false }
    end

    assert_equal [], attached
    assert_not blob_stored?(blobs.first)
    assert_equal 0, ActiveStorage::Blob.where(id: blobs.first.id).count
    assert_equal 0, @entry.reload.images.count
  end

  test "the condition runs on the freshly locked row" do
    title = nil
    Shiplog::Entry.where(id: @entry.id).update_all(title: "Changed elsewhere")
    tracking_uploads { @entry.add_images([ file(:gif) ]) { (title = @entry.title) && true } }
    assert_equal "Changed elsewhere", title
  end

  test "a failing purge does not stop the others" do
    blobs = nil
    stored = nil
    assert_raises(IOError) do
      tracking_uploads(fail_at: 3) do |uploaded|
        blobs = uploaded
        original = ActiveStorage::Blob.instance_method(:purge)
        first = true
        ActiveStorage::Blob.send(:define_method, :purge) { first ? (first = false; raise("purge failed")) : original.bind_call(self) }
        begin
          @entry.add_images([ file(:png), file(:gif), file(:jpg) ])
        ensure
          ActiveStorage::Blob.send(:define_method, :purge, original)
          stored = blobs.map { |blob| blob_stored?(blob) }
        end
      end
    end
    assert_equal [ true, false ], stored
  end
end
