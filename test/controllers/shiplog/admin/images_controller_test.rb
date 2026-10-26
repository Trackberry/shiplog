require "test_helper"

class Shiplog::Admin::ImagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @entry = shiplog_entries(:csv_change_draft)
    @base = "/admin/shiplog/entries/#{@entry.id}"
  end

  def add(*types)
    @entry.add_images(types.each_with_index.map { |type, i| { io: StringIO.new(image_bytes(type)), filename: "shot-#{i}.#{type}", content_type: Shiplog::ImageType::EXTENSIONS.key(type.to_s.sub("jpg", "jpg")) || "image/png" } })
  end

  def blob_ids = @entry.reload.ordered_images.map(&:blob_id)

  test "the edit page lists the images in order with alt text, remove and move buttons, and an upload form" do
    first, second = add(:png, :gif)
    get "#{@base}/edit"

    assert_response :ok
    assert_select ".shiplog-admin-images__item", 2
    assert_select ".shiplog-admin-images__item:first-child" do
      assert_select "img[alt=?]", "Better CSV validation"
      assert_select "input[name=alt][placeholder]"
      assert_select "form[action=?] button, form[action=?] input[type=submit]", "#{@base}/images/#{first.blob_id}", "#{@base}/images/#{first.blob_id}"
      assert_select "form[action^=?]", "#{@base}/images/#{first.blob_id}/move?direction=down"
      assert_select "form[action*=?]", "direction=up", 0
    end
    assert_select ".shiplog-admin-images__item:last-child form[action*=?]", "direction=up"
    assert_select ".shiplog-admin-images__item:last-child form[action*=?]", "direction=down", 0
    assert_select "form[action=?][enctype='multipart/form-data'] input[type=file][multiple][name='images[]']", "#{@base}/images"
    assert second
  end

  test "the page keeps the inbox filter params in every image action" do
    first, = add(:png)
    get "#{@base}/edit", params: { status: "draft", kind: "change", page: 2 }
    assert_select "form[action=?]", "#{@base}/images/#{first.blob_id}?kind=change&page=2&status=draft", minimum: 1
    assert_select "form[action=?]", "#{@base}/images?kind=change&page=2&status=draft"
  end

  test "uploads several images at once, appended in order" do
    assert_difference -> { @entry.reload.images.count }, 3 do
      post "#{@base}/images", params: { images: [ image_upload(:png), image_upload(:jpg), image_upload(:webp) ], status: "draft" }
    end

    assert_redirected_to "#{@base}/edit?status=draft"
    assert_equal "3 images added.", flash[:notice]
    images = @entry.reload.ordered_images
    assert_equal %w[image/png image/jpeg image/webp], images.map { |image| image.blob.content_type }
    assert_equal images.map(&:blob_id), @entry.image_order
  end

  test "the type comes from the bytes, not from the name or the declared type" do
    post "#{@base}/images", params: { images: [ image_upload(:gif, bytes: image_bytes(:gif), mime: "text/plain", name: "shot.txt") ] }

    assert_equal [ "image/gif" ], @entry.reload.ordered_images.map { |image| image.blob.content_type }
  end

  test "rejects SVG, HTML and renamed files, and adds nothing when one is bad" do
    [ [ :svg, "evil.svg" ], [ :html, "page.png" ], [ :svg, "evil.png" ] ].each do |type, name|
      post "#{@base}/images", params: { images: [ image_upload(:png), image_upload(type, name:) ] }
      assert_redirected_to "#{@base}/edit"
      assert_match name, flash[:alert]
      assert_equal 0, @entry.reload.images.count, name
    end
  end

  test "rejects an empty file and a file over 5 MB" do
    empty = image_upload(:png, bytes: "", name: "empty.png")
    huge = image_upload(:png, bytes: image_bytes(:png).ljust(Shiplog::ImageType::MAX_BYTES + 1, "a"), name: "huge.png")

    [ empty, huge ].each do |file|
      post "#{@base}/images", params: { images: [ file ] }
      assert_match file.original_filename, flash[:alert]
    end
    assert_equal 0, @entry.reload.images.count
  end

  test "an upload without files, or with a plain string, says so" do
    post "#{@base}/images"
    assert_equal "Choose at least one image.", flash[:alert]
    post "#{@base}/images", params: { images: [ "not a file" ] }
    assert_equal "Choose at least one image.", flash[:alert]
  end

  test "saves an alt text, trims it and clears it when blank" do
    image, = add(:png)

    patch "#{@base}/images/#{image.blob_id}", params: { alt: "  The   dark theme  " }
    assert_redirected_to "#{@base}/edit"
    assert_equal "The dark theme", @entry.reload.image_alt(image)

    patch "#{@base}/images/#{image.blob_id}", params: { alt: "" }
    assert_equal @entry.title, @entry.reload.image_alt(image)
    assert_empty @entry.image_alts
  end

  test "an alt text is cut at 300 characters" do
    image, = add(:png)
    patch "#{@base}/images/#{image.blob_id}", params: { alt: "a" * 500 }
    assert_equal 300, @entry.reload.image_alt(image).length
  end

  test "removes an image and its alt text" do
    first, second = add(:png, :gif)
    patch "#{@base}/images/#{first.blob_id}", params: { alt: "Gone" }

    assert_enqueued_with(job: ActiveStorage::PurgeJob) { delete "#{@base}/images/#{first.blob_id}" }

    assert_redirected_to "#{@base}/edit"
    assert_equal [ second.blob_id ], blob_ids
    assert_equal [ second.blob_id ], @entry.image_order
    assert_empty @entry.image_alts
  end

  test "moves an image up or down, and moving past an end changes nothing" do
    a, b, c = add(:png, :gif, :jpg).map(&:blob_id)

    post "#{@base}/images/#{c}/move", params: { direction: "up" }
    assert_equal [ a, c, b ], blob_ids
    post "#{@base}/images/#{a}/move", params: { direction: "down" }
    assert_equal [ c, a, b ], blob_ids
    post "#{@base}/images/#{c}/move", params: { direction: "up" }
    assert_equal [ c, a, b ], blob_ids
    post "#{@base}/images/#{b}/move", params: { direction: "down" }
    assert_equal [ c, a, b ], blob_ids
  end

  test "an image of another entry, or an unknown one, is a 404" do
    other = shiplog_entries(:dark_mode_feature)
    foreign = other.add_images([ { io: StringIO.new(image_bytes(:png)), filename: "x.png", content_type: "image/png" } ]).first

    patch "#{@base}/images/#{foreign.blob_id}", params: { alt: "x" }
    assert_response :not_found
    delete "#{@base}/images/#{foreign.blob_id}"
    assert_response :not_found
    post "#{@base}/images/#{foreign.blob_id}/move", params: { direction: "up" }
    assert_response :not_found
    delete "#{@base}/images/0"
    assert_response :not_found
    assert_equal 1, other.reload.images.count
  end

  test "images can be managed on an approved entry" do
    entry = shiplog_entries(:dark_mode_feature)
    post "/admin/shiplog/entries/#{entry.id}/images", params: { images: [ image_upload(:png) ] }
    assert_equal 1, entry.reload.images.count
    assert entry.approved?
  end

  test "everything is a 404 and the edit page shows no section while screenshots are off" do
    Shiplog.config.images = false
    get "#{@base}/edit"
    assert_response :ok
    assert_select ".shiplog-admin-images", 0

    post "#{@base}/images", params: { images: [ image_upload(:png) ] }
    assert_response :not_found
    assert_equal 0, @entry.reload.images.count
  end

  test "the edit page has no section without Active Storage" do
    without_active_storage do
      get "#{@base}/edit"
      assert_response :ok
      assert_select ".shiplog-admin-images", 0
    end
  end

  test "the actions need an admin" do
    Shiplog.config.authorize_admin = ->(_controller) { false }
    post "#{@base}/images", params: { images: [ image_upload(:png) ] }
    assert_response :forbidden
  end
end
