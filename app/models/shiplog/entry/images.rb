# An entry's screenshots: Active Storage attachments, their order (`image_order`, blob ids) and alt texts
# (`image_alts`, blob id => text). Without Active Storage in the host nothing is declared and every method
# answers "no images".
module Shiplog::Entry::Images
  extend ActiveSupport::Concern

  ALT_MAX_LENGTH = 300

  included do
    has_many_attached :images if Shiplog.active_storage?

    scope :with_images_loaded, -> { Shiplog.images? ? includes(images_attachments: :blob) : all }
  end

  # The attachments in the admin's order: those listed in image_order first, the others (attached without
  # being listed) after, oldest first.
  def ordered_images
    return [] unless Shiplog.active_storage?

    by_blob = images.attachments.index_by(&:blob_id)
    listed = Array(image_order).filter_map { |id| by_blob.delete(Integer(id, exception: false)) }
    listed + by_blob.values.sort_by(&:id)
  end

  # The alt text of an image: the one set for its blob, else the entry's title.
  def image_alt(attachment)
    image_alts.to_h[attachment.blob_id.to_s].presence || title.to_s
  end

  # What public pages depend on, for ETags: each image's blob id and alt text, in order.
  def image_etag_parts
    ordered_images.map { |attachment| [ attachment.blob_id, image_alt(attachment) ] }
  end

  def find_image(blob_id)
    images.attachments.find { |attachment| attachment.blob_id == Integer(blob_id, exception: false) } if Shiplog.active_storage?
  end

  # Attaches files ({ io:, filename:, content_type: }, already validated) after the existing images and returns
  # the attachments. The caller holds the row lock when it must not race.
  def add_images(files)
    blobs = files.map { |file| ActiveStorage::Blob.create_and_upload!(**file, identify: false) }
    before = ordered_images.map(&:blob_id)
    images.attach(blobs)
    update!(image_order: before + blobs.map(&:id))
    images_attachments.reset
    ordered_images.last(blobs.size)
  end

  def remove_image(blob_id)
    with_lock do
      attachment = find_image(blob_id)
      next false unless attachment

      ids = ordered_images.map(&:blob_id) - [ attachment.blob_id ]
      attachment.purge_later
      update!(image_order: ids, image_alts: image_alts.to_h.except(attachment.blob_id.to_s))
    end
  end

  # direction: :up or :down. Moving past either end changes nothing.
  def move_image(blob_id, direction)
    with_lock do
      ids = ordered_images.map(&:blob_id)
      index = ids.index(Integer(blob_id, exception: false))
      target = index && (direction.to_sym == :up ? index - 1 : index + 1)
      next false unless target && target.between?(0, ids.size - 1)

      ids[index], ids[target] = ids[target], ids[index]
      update!(image_order: ids)
    end
  end

  def update_image_alt(blob_id, text)
    with_lock do
      attachment = find_image(blob_id)
      next false unless attachment

      alt = text.to_s.squish.first(ALT_MAX_LENGTH)
      alts = image_alts.to_h.except(attachment.blob_id.to_s)
      alts[attachment.blob_id.to_s] = alt if alt.present?
      update!(image_alts: alts)
    end
  end
end
