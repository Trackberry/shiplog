module Shiplog
  # What an entry image may be: PNG, JPEG, GIF or WebP, recognised by the file's first bytes (never by its
  # extension or a declared content type), and at most 5 MB.
  module ImageType
    MAX_BYTES = 5 * 1024 * 1024
    # Bytes needed to tell the types apart.
    SNIFF_LENGTH = 12
    EXTENSIONS = { "image/png" => "png", "image/jpeg" => "jpg", "image/gif" => "gif", "image/webp" => "webp" }.freeze

    # The content type of the data starting with `head` (a binary String), or nil for anything else (SVG, HTML...).
    def self.detect(head)
      head = head.to_s.b
      if head.start_with?("\x89PNG\r\n\x1A\n".b) then "image/png"
      elsif head.start_with?("\xFF\xD8\xFF".b) then "image/jpeg"
      elsif head.start_with?("GIF87a".b, "GIF89a".b) then "image/gif"
      elsif head.bytesize >= SNIFF_LENGTH && head.byteslice(0, 4) == "RIFF".b && head.byteslice(8, 4) == "WEBP".b then "image/webp"
      end
    end
  end
end
