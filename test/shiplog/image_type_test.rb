require "test_helper"

class Shiplog::ImageTypeTest < ActiveSupport::TestCase
  test "recognises PNG, JPEG, GIF and WebP by their first bytes" do
    { png: "image/png", jpg: "image/jpeg", gif: "image/gif", webp: "image/webp" }.each do |type, content_type|
      assert_equal content_type, Shiplog::ImageType.detect(image_bytes(type).first(Shiplog::ImageType::SNIFF_LENGTH)), type
    end
  end

  test "refuses SVG, HTML, empty and truncated data" do
    [ image_bytes(:svg), image_bytes(:html), "", nil, "RIFF\x00\x00\x00\x00WEBX", "RIFF", "GIF" ].each do |data|
      assert_nil Shiplog::ImageType.detect(data), data.inspect
    end
  end

  test "a RIFF file that is not WebP is refused" do
    assert_nil Shiplog::ImageType.detect("RIFF\x10\x00\x00\x00WAVEfmt ".b)
  end
end
