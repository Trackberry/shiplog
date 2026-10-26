module Shiplog
  module Admin
    class EntriesController < ApplicationController
      PER_PAGE = 50
      MAX_PAGE = 100_000

      before_action :set_entry, only: %i[edit update]

      def index
        @status = Entry.statuses.key(params[:status].to_s) || "draft"
        @kind = Entry.kinds.key(params[:kind].to_s)
        @page = page_number
        scope = Entry.where(status: @status)
        scope = scope.where(kind: @kind) if @kind
        records = scope.includes(:subject).order(updated_at: :desc, id: :desc)
          .offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
        @more = records.size > PER_PAGE
        @entries = records.first(PER_PAGE)
      end

      def edit
      end

      def update
        if @entry.update(entry_params)
          redirect_to root_path, notice: t("shiplog.admin.entries.saved")
        else
          render :edit, status: :unprocessable_content
        end
      end

      private

      def set_entry
        @entry = Entry.find(params[:id])
      end

      def entry_params
        params.expect(entry: %i[title body released_on])
      end

      def page_number
        Integer(params[:page].to_s, 10, exception: false).to_i.clamp(1, MAX_PAGE)
      end
    end
  end
end
