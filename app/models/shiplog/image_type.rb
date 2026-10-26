module Shiplog
  # What an entry image may be: PNG, JPEG, GIF or WebP, recognised by the file's first bytes (never by its
  # extension or a declared content type), at most 5 MB, at most 10,000 pixels on a side and 40 megapixels. The
  # pixel size is read from the header, without decoding anything, before an image processor ever sees the file
  # (a decompression bomb is a tiny file declaring a huge size).
  module ImageType
    MAX_BYTES = 5 * 1024 * 1024
    MAX_SIDE = 10_000
    MAX_PIXELS = 40_000_000
    # Bytes needed to tell the types apart.
    SNIFF_LENGTH = 12
    EXTENSIONS = { "image/png" => "png", "image/jpeg" => "jpg", "image/gif" => "gif", "image/webp" => "webp" }.freeze

    Invalid = Class.new(StandardError)
    Info = Data.define(:content_type, :width, :height)

    # JPEG frame headers (SOF0..SOF15) are the markers 0xC0..0xCF except these three, which are not frames.
    JPEG_NOT_FRAME = [ 0xC4, 0xC8, 0xCC ].freeze # DHT, JPG, DAC

    # The content type of the data starting with `head` (a binary String), or nil for anything else (SVG, HTML...).
    def self.detect(head)
      head = head.to_s.b
      if head.start_with?("\x89PNG\r\n\x1A\n".b) then "image/png"
      elsif head.start_with?("\xFF\xD8\xFF".b) then "image/jpeg"
      elsif head.start_with?("GIF87a".b, "GIF89a".b) then "image/gif"
      elsif head.bytesize >= SNIFF_LENGTH && head.byteslice(0, 4) == "RIFF".b && head.byteslice(8, 4) == "WEBP".b then "image/webp"
      end
    end

    # The type and pixel size of the image `data` (a String of at most MAX_BYTES), or raises Invalid: not one of
    # the four types, a size that can't be read from the header, or a size over the limits.
    def self.analyze(data)
      data = data.to_s.b
      content_type = detect(data.byteslice(0, SNIFF_LENGTH)) or raise Invalid, "not a PNG, JPEG, GIF or WebP image"
      width, height = dimensions(data, content_type)
      raise Invalid, "the image's dimensions can't be read" unless width&.positive? && height&.positive?
      raise Invalid, "#{width}x#{height} pixels is too large (at most #{MAX_SIDE} on a side and #{MAX_PIXELS / 1_000_000} megapixels)" if width > MAX_SIDE || height > MAX_SIDE || width * height > MAX_PIXELS

      Info.new(content_type:, width:, height:)
    end

    # [width, height] read from the header of `data`, or nil when the header is truncated or malformed.
    def self.dimensions(data, content_type)
      case content_type
      when "image/png" then png_dimensions(data)
      when "image/gif" then gif_dimensions(data)
      when "image/webp" then webp_dimensions(data)
      when "image/jpeg" then jpeg_dimensions(data.byteslice(0, MAX_BYTES))
      end
    end

    # The IHDR chunk comes first: 8 bytes of signature, length, "IHDR", then width and height (big-endian).
    def self.png_dimensions(data)
      data.byteslice(16, 8).unpack("NN") if data.bytesize >= 24 && data.byteslice(12, 4) == "IHDR".b
    end

    # The logical screen descriptor follows the 6-byte signature: width and height (little-endian).
    def self.gif_dimensions(data)
      data.byteslice(6, 4).unpack("vv") if data.bytesize >= 10
    end

    # The first chunk, at byte 12, says which kind of WebP it is.
    def self.webp_dimensions(data)
      case data.byteslice(12, 4)
      when "VP8 ".b # lossy: frame tag (3 bytes), start code 9D 01 2A, 14-bit width and height
        data.byteslice(26, 4).unpack("vv").map { |value| value & 0x3FFF } if data.bytesize >= 30 && data.byteslice(23, 3) == "\x9D\x01\x2A".b
      when "VP8L".b # lossless: signature 0x2F, then 14 bits of width - 1 and 14 bits of height - 1
        if data.bytesize >= 25 && data.getbyte(20) == 0x2F
          bits = data.byteslice(21, 4).unpack1("V")
          [ (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1 ]
        end
      when "VP8X".b # extended: flags, then the canvas size - 1 on 24 bits each
        if data.bytesize >= 30
          width, height = (data.byteslice(24, 3) + "\x00".b).unpack1("V"), (data.byteslice(27, 3) + "\x00".b).unpack1("V")
          [ width + 1, height + 1 ]
        end
      end
    end

    # Walks the segments from the start until a frame header (SOF0..SOF15, but not DHT, DAC and JPG). Stops at the
    # scan (SOS) or the end of the image: a frame header comes before both. Each step moves forward at least two
    # bytes, over data already capped at MAX_BYTES.
    def self.jpeg_dimensions(data)
      position = 2
      size = data.bytesize
      while position < size
        return unless data.getbyte(position) == 0xFF

        position += 1 while position < size && data.getbyte(position) == 0xFF # fill bytes
        marker = data.getbyte(position)
        position += 1
        return if marker.nil? || marker == 0xD9 || marker == 0xDA # end of image, start of scan
        next if marker.zero? || marker == 0x01 || marker.between?(0xD0, 0xD8) # no length

        return if position + 2 > size

        length = data.byteslice(position, 2).unpack1("n")
        return if length < 2

        if marker.between?(0xC0, 0xCF) && !JPEG_NOT_FRAME.include?(marker)
          return unless position + 7 <= size

          height, width = data.byteslice(position + 3, 4).unpack("nn")
          return [ width, height ]
        end
        position += length
      end
      nil
    end
  end
end
