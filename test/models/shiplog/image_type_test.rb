require "test_helper"

class Shiplog::ImageTypeTest < ActiveSupport::TestCase
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze

  def png(width, height) = PNG_SIGNATURE + [ 13 ].pack("N") + "IHDR" + [ width, height ].pack("NN") + "\x08\x06\x00\x00\x00".b

  def gif(width, height) = "GIF89a".b + [ width, height ].pack("vv") + "\x00\x00\x00".b

  def riff(chunk) = "RIFF".b + [ chunk.bytesize + 4 ].pack("V") + "WEBP".b + chunk

  def webp_lossy(width, height) = riff("VP8 ".b + [ 10 ].pack("V") + "\x00\x00\x00\x9D\x01\x2A".b + [ width, height ].pack("vv"))

  def webp_lossless(width, height) = riff("VP8L".b + [ 5 ].pack("V") + "\x2F".b + [ ((height - 1) << 14) | (width - 1) ].pack("V"))

  def webp_extended(width, height)
    riff("VP8X".b + [ 10 ].pack("V") + "\x00\x00\x00\x00".b + [ width - 1 ].pack("V").byteslice(0, 3) + [ height - 1 ].pack("V").byteslice(0, 3))
  end

  def segment(marker, payload) = "\xFF".b + marker.chr + [ payload.bytesize + 2 ].pack("n") + payload.b

  # A JPEG header: APP0, a decoy segment with bytes that look like a frame header, then the frame header.
  def jpeg(width, height, marker: 0xC0, decoy: 0xC4)
    frame = "\x08".b + [ height, width ].pack("nn") + "\x01\x01\x11\x00".b
    "\xFF\xD8".b + segment(0xE0, "JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00") +
      segment(decoy, "\x08\x00\x01\x00\x01\x00\x00\x00") + segment(marker, frame) + segment(0xDA, "\x01\x01\x00\x00\x3F\x00")
  end

  def dimensions(data) = Shiplog::ImageType.analyze(data).then { |info| [ info.width, info.height ] }

  def assert_rejected(data, pattern = nil)
    error = assert_raises(Shiplog::ImageType::Invalid) { Shiplog::ImageType.analyze(data) }
    assert_match pattern, error.message if pattern
  end

  test "reads the dimensions of every type from the header" do
    assert_equal [ 640, 480 ], dimensions(png(640, 480))
    assert_equal [ 640, 480 ], dimensions(gif(640, 480))
    assert_equal [ 640, 480 ], dimensions(webp_lossy(640, 480))
    assert_equal [ 640, 480 ], dimensions(webp_lossless(640, 480))
    assert_equal [ 640, 480 ], dimensions(webp_extended(640, 480))
    assert_equal [ 640, 480 ], dimensions(jpeg(640, 480))
  end

  test "the type comes with the dimensions" do
    assert_equal "image/webp", Shiplog::ImageType.analyze(webp_lossless(2, 2)).content_type
    assert_equal "image/jpeg", Shiplog::ImageType.analyze(jpeg(2, 2)).content_type
  end

  test "the real fixtures are 1x1" do
    %i[png jpg gif webp].each { |type| assert_equal [ 1, 1 ], dimensions(image_bytes(type)), type }
  end

  test "every JPEG frame marker counts, except DHT, DAC and JPG" do
    [ 0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF ].each do |marker|
      assert_equal [ 300, 200 ], dimensions(jpeg(300, 200, marker:)), marker.to_s(16)
    end
    [ 0xC4, 0xC8, 0xCC ].each do |marker|
      assert_rejected jpeg(300, 200, marker:, decoy: 0xE1)
    end
  end

  test "JPEG segments before the frame header are skipped, fill bytes included" do
    data = "\xFF\xD8".b + segment(0xFE, "a comment with \xFF\xC0 inside".b) + "\xFF\xFF".b + segment(0xC2, "\x08".b + [ 90, 120 ].pack("nn") + "\x01\x01\x11\x00".b)
    assert_equal [ 120, 90 ], dimensions(data)
  end

  test "a JPEG whose scan starts before any frame header is refused" do
    assert_rejected "\xFF\xD8".b + segment(0xDA, "\x01\x01\x00\x00\x3F\x00") + segment(0xC0, "\x08".b + [ 5, 5 ].pack("nn") + "\x01\x01\x11\x00".b), /dimensions/
  end

  test "an image over 10,000 pixels on a side is refused, 10,000 is not" do
    assert_equal [ 10_000, 100 ], dimensions(png(10_000, 100))
    [ png(10_001, 1), png(1, 10_001), gif(10_001, 1), gif(1, 65_535), webp_lossy(10_001, 1), webp_lossless(1, 10_001),
      webp_extended(16_000_000, 1), jpeg(1, 10_001), jpeg(65_535, 1, marker: 0xC2) ].each do |data|
      assert_rejected data, /too large/
    end
  end

  test "an image over 40 megapixels is refused, 40 megapixels is not" do
    assert_equal [ 8_000, 5_000 ], dimensions(png(8_000, 5_000))
    assert_equal [ 5_000, 8_000 ], dimensions(webp_lossless(5_000, 8_000))
    [ png(8_000, 5_001), gif(5_001, 8_000), webp_lossy(9_000, 4_500), webp_extended(5_001, 8_000), jpeg(8_000, 5_001) ].each do |data|
      assert_rejected data, /too large/
    end
  end

  test "an image whose dimensions can't be read is refused" do
    [ PNG_SIGNATURE, PNG_SIGNATURE + "\x00\x00\x00\x0DIHDR\x00\x00".b, png(0, 5), png(5, 0),
      PNG_SIGNATURE + [ 13 ].pack("N") + "IDAT" + [ 5, 5 ].pack("NN"),
      "GIF89a\x01".b, gif(0, 3), webp_lossy(0, 0),
      riff("VP8 ".b + [ 10 ].pack("V") + "\x00\x00\x00\x00\x00\x00".b + [ 5, 5 ].pack("vv")), # no start code
      riff("VP8L".b + [ 5 ].pack("V") + "\x2E".b + [ 1 ].pack("V")), # wrong signature byte
      riff("ALPH".b + [ 4 ].pack("V") + "abcd"), riff("VP8X".b + [ 10 ].pack("V") + "\x00".b * 4),
      "\xFF\xD8\xFF".b, "\xFF\xD8".b + segment(0xE0, "x"), "\xFF\xD8".b + "\xFF\xC0\x00\x0B\x08\x00".b, jpeg(0, 10) ].each do |data|
      assert_rejected data, /dimensions/
    end
  end

  test "not an image at all is refused, whatever the type" do
    assert_rejected "<svg xmlns='http://www.w3.org/2000/svg'/>", /not a PNG/
    assert_rejected "", /not a PNG/
    assert_rejected nil, /not a PNG/
  end

  test "the JPEG scan stops at the size limit" do
    padding = segment(0xFE, "a" * 60_000)
    data = "\xFF\xD8".b + (padding * ((Shiplog::ImageType::MAX_BYTES / padding.bytesize) + 1)) + segment(0xC0, "\x08".b + [ 5, 5 ].pack("nn") + "\x01\x01\x11\x00".b)
    assert_operator data.bytesize, :>, Shiplog::ImageType::MAX_BYTES
    assert_rejected data, /dimensions/
  end
end
