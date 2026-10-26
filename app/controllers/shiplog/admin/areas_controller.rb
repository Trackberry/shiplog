module Shiplog
  module Admin
    # The Areas page: product areas with their entry counts; rename, edit the translated names, delete. Reordering, merging and detection
    # are their own small controllers.
    class AreasController < ApplicationController
      before_action :set_area, only: %i[update destroy]

      def index
        @areas = Area.ordered.to_a
        @counts = Area.entry_counts
        @detection = Setting.read(DetectAreasJob::SETTING)
      end

      def update
        if @area.update(area_attributes)
          redirect_to areas_path, notice: t("shiplog.admin.areas.renamed", default: "Area renamed.")
        else
          redirect_to areas_path, alert: @area.errors.full_messages.to_sentence
        end
      end

      def destroy
        @area.destroy!
        redirect_to areas_path, notice: t("shiplog.admin.areas.deleted", default: "Area deleted. Its entries have no area now.")
      end

      private

      # The name, and the translated names of the configured locales. A rename drops the translations (they were of
      # the old name) and enqueues a new translation, so the translations sent with it are ignored; without a
      # rename they are kept as the admin typed them (an empty field removes one), over any earlier translation.
      def area_attributes
        permitted = params.expect(area: [ :name, { name_translations: {} } ])
        attributes = { name: permitted[:name] }
        submitted = permitted[:name_translations]
        if submitted && permitted[:name].to_s.squish == @area.name
          locales = Shiplog.config.locales.map(&:to_s)
          attributes[:name_translations] = @area.name_translations.merge(submitted.to_h.slice(*locales).select { |_locale, value| value.is_a?(String) })
        end
        attributes
      end

      def set_area
        @area = Area.find(params[:id])
      end
    end
  end
end
