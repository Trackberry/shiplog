module Shiplog
  module Admin
    module Entries
      # An entry's screenshots on the edit page: upload, alt text, remove. :id is the image's blob id, the key of
      # the entry's order and alt texts. Not found while screenshots are off.
      class ImagesController < ApplicationController
        before_action :require_images
        before_action :set_entry

        def create
          files = uploads
          return back(alert: t("shiplog.admin.entries.images.none_selected", default: "Choose at least one image.")) if files.empty?

          rejected = files.reject { |file| acceptable?(file) }
          if rejected.any?
            names = rejected.map { |file| file.original_filename.to_s.scrub.first(100) }.to_sentence
            return back(alert: t("shiplog.admin.entries.images.rejected", names:, default: "Not added, only PNG, JPEG, GIF and WebP images up to 5 MB are accepted: %{names}"))
          end

          @entry.add_images(files.map { |file| attachable(file) }) # uploads first, locks only to attach
          back(notice: t("shiplog.admin.entries.images.added", count: files.size, default: { one: "Image added.", other: "%{count} images added." }))
        end

        def update
          return head(:not_found) unless @entry.find_image(params[:id])

          @entry.update_image_alt(params[:id], params[:alt])
          back(notice: t("shiplog.admin.entries.images.alt_saved", default: "Alt text saved."))
        end

        def destroy
          return head(:not_found) unless @entry.find_image(params[:id])

          @entry.remove_image(params[:id])
          back(notice: t("shiplog.admin.entries.images.removed", default: "Image removed."))
        end

        private

        def require_images
          head :not_found unless Shiplog.images?
        end

        def set_entry
          @entry = Entry.find(params[:entry_id])
        end

        def back(**flash)
          redirect_to edit_entry_path(@entry, inbox_filter_params), **flash
        end

        def uploads
          Array(params[:images]).select { |file| file.is_a?(ActionDispatch::Http::UploadedFile) }
        end

        # Decided by the file's first bytes and size, never by the declared name or content type.
        def acceptable?(file)
          return false unless file.size.between?(1, ImageType::MAX_BYTES)

          file.rewind
          head = file.read(ImageType::SNIFF_LENGTH)
          file.rewind
          ImageType.detect(head).present?
        end

        def attachable(file)
          file.rewind
          content_type = ImageType.detect(file.read(ImageType::SNIFF_LENGTH))
          file.rewind
          { io: file.tempfile, filename: file.original_filename.to_s.scrub.presence || "image", content_type: }
        end
      end
    end
  end
end
