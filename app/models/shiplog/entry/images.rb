# An entry's screenshots: Active Storage attachments, their order (`image_order`, blob ids) and alt texts
# (`image_alts`, blob id => text). Without Active Storage in the host nothing is declared and every method
# answers "no images".
module Shiplog::Entry::Images
  extend ActiveSupport::Concern

  ALT_MAX_LENGTH = 300

  included do
    has_many_attached :images if Shiplog.active_storage_loaded?

    scope :with_images_loaded, -> { Shiplog.images? ? includes(images_attachments: :blob) : all }
  end

  # The attachments in the admin's order: those listed in image_order first, the others (attached without
  # being listed) after, oldest first.
  def ordered_images
    return [] unless Shiplog.active_storage?

    by_blob = images.attachments.index_by { |attachment| attachment.blob_id.to_s }
    listed = Array(image_order).filter_map { |id| by_blob.delete(id.to_s) }
    listed + by_blob.values.sort_by(&:id)
  end

  # The alt texts by blob id (a String), whatever the column holds: anything but a Hash counts as none.
  def image_alts_by_blob = image_alts.is_a?(Hash) ? image_alts : {}

  # The alt text an admin set for an image, or nil.
  def custom_image_alt(attachment) = image_alts_by_blob[attachment.blob_id.to_s].presence

  # The alt text of an image: the one set for its blob, else the entry's title.
  def image_alt(attachment)
    custom_image_alt(attachment) || display_title.to_s
  end

  # What public pages depend on, for ETags: each image's blob id, alt text and size (the width and height
  # attributes of the markup), in order.
  def image_etag_parts
    ordered_images.map { |attachment| [ attachment.blob_id, image_alt(attachment), attachment.blob.metadata[:width], attachment.blob.metadata[:height] ] }
  end

  # Blob ids are compared as strings: they may be integers or UUIDs, in the column, in the URL and in the table.
  def find_image(blob_id)
    images.attachments.find { |attachment| attachment.blob_id.to_s == blob_id.to_s } if Shiplog.active_storage?
  end

  # Attaches files ({ io:, filename:, content_type:, metadata: }, already validated) after the existing images and
  # returns the attachments. The files are uploaded first, with no lock held (storage can be slow); only the
  # attaching and the bookkeeping of image_order happen under the entry's row lock, so a racing request can't
  # interleave. The block, when given, runs under the lock on the freshly loaded row: when it returns falsy
  # nothing is attached and [] is returned. Nothing is attached, and every uploaded blob (file included) is
  # purged, when anything fails or the block declines: all or nothing.
  def add_images(files)
    blobs = upload_blobs(files)
    attached = with_lock { attach_blobs(blobs) if !block_given? || yield }
    purge_blobs(blobs) unless attached
    attached || []
  rescue StandardError
    purge_blobs(blobs) if blobs
    raise
  end

  def remove_image(blob_id)
    with_lock do
      attachment = find_image(blob_id)
      next false unless attachment

      ids = ordered_images.map(&:blob_id) - [ attachment.blob_id ]
      attachment.purge_later
      update!(image_order: ids, image_alts: image_alts_by_blob.except(attachment.blob_id.to_s))
    end
  end

  # direction: :up or :down. Moving past either end changes nothing.
  def move_image(blob_id, direction)
    with_lock do
      ids = ordered_images.map(&:blob_id)
      index = ids.index { |id| id.to_s == blob_id.to_s }
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
      alts = image_alts_by_blob.except(attachment.blob_id.to_s)
      alts[attachment.blob_id.to_s] = alt if alt.present?
      update!(image_alts: alts)
    end
  end

  private

  def upload_blobs(files)
    blobs = []
    files.each { |file| blobs << ActiveStorage::Blob.create_and_upload!(**file, identify: false) }
    blobs
  rescue StandardError
    purge_blobs(blobs)
    raise
  end

  # Under the row lock.
  def attach_blobs(blobs)
    before = ordered_images.map(&:blob_id)
    images.attach(blobs)
    update!(image_order: before + blobs.map(&:id))
    images_attachments.reset
    ordered_images.last(blobs.size)
  end

  # Deletes blobs and their stored files. A failure on one is logged and doesn't stop the others.
  def purge_blobs(blobs)
    blobs.each do |blob|
      blob.purge
    rescue StandardError => error
      Rails.logger&.warn("[shiplog] Could not purge blob #{blob.id} of entry #{id}: #{error.class}: #{error.message}")
    end
  end
end
