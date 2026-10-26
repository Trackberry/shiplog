require "test_helper"

# Thumbnails in the admin are variants only when image_processing is loaded and has a processor to run.
class Shiplog::ImageVariantsTest < ActionView::TestCase
  include Shiplog::Admin::EntriesHelper

  def loaded_specs(*names) = names.index_with { Gem::Specification.new }.transform_keys(&:to_s)

  def with_gems(*names, vips: false, &block)
    Shiplog.reset_images_checks!
    with_stub(Gem, :loaded_specs, ->(*) { loaded_specs(*names) }) do
      with_stub(Shiplog, :vips_loads?, ->(*) { vips }, &block)
    end
  ensure
    Shiplog.reset_images_checks!
  end

  test "no variants without image_processing, whatever processor is there" do
    with_gems("ruby-vips", "mini_magick", vips: true) { assert_not Shiplog.image_variants? }
  end

  test "no variants with image_processing but no processor" do
    with_gems("image_processing") { assert_not Shiplog.image_variants? }
    with_gems("image_processing", "ruby-vips", vips: false) { assert_not Shiplog.image_variants? }
  end

  test "variants with image_processing and ruby-vips that loads, or mini_magick" do
    with_gems("image_processing", "ruby-vips", vips: true) { assert Shiplog.image_variants? }
    with_gems("image_processing", "mini_magick") { assert Shiplog.image_variants? }
  end

  test "the answer is remembered" do
    calls = 0
    Shiplog.reset_images_checks!
    with_stub(Gem, :loaded_specs, ->(*) { calls += 1; loaded_specs("image_processing", "mini_magick") }) do
      Shiplog.image_variants?
      first = calls
      3.times { Shiplog.image_variants? }
      assert_equal first, calls
    end
  ensure
    Shiplog.reset_images_checks!
  end

  test "the thumbnail is the original when variants are not available, and never calls variant" do
    image = shiplog_entries(:dark_mode_feature).add_images([ { io: StringIO.new(image_bytes(:png)), filename: "a.png", content_type: "image/png" } ]).first
    with_stub(self, :polymorphic_path, ->(source) { source.class.name }) do
      with_stub(Shiplog, :image_variants?, ->(*) { false }) do
        with_stub(image, :variant, ->(*) { flunk "a variant must not be built" }) do
          assert_equal "ActiveStorage::Attachment", image_thumbnail_path(image)
        end
      end
    end
  end

  test "the thumbnail is a 200x200 variant when variants are available and the image is variable" do
    image = shiplog_entries(:dark_mode_feature).add_images([ { io: StringIO.new(image_bytes(:png)), filename: "a.png", content_type: "image/png" } ]).first
    requested = nil
    with_stub(self, :polymorphic_path, ->(source) { source }) do
      with_stub(Shiplog, :image_variants?, ->(*) { true }) do
        with_stub(image, :variable?, ->(*) { true }) do
          with_stub(image, :variant, ->(**options) { requested = options; :variant }) do
            assert_equal :variant, image_thumbnail_path(image)
          end
        end
      end
    end
    assert_equal({ resize_to_limit: [ 200, 200 ] }, requested)
  end
end
