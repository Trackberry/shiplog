module Shiplog
  module Admin
    class BoardsController < ApplicationController
      def show
        @columns = Roadmap.new(published_only: false).columns
        ActiveRecord::Associations::Preloader.new(records: @columns.values.flatten.map(&:issue), associations: :repository).call
      end

      def update
        if request.format.json?
          update_json
        else
          update_form
        end
      end

      private

      def update_json
        ids = params[:issue_ids]
        return render_json_error("issue_ids required") unless ids.is_a?(Array) && ids.any?

        BoardArrangement.new(column: params[:column], moved_id: params[:moved_id], issue_ids: ids).save!
        head :no_content
      rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
        render_json_error(error.message)
      end

      def update_form
        issue = Issue.find(params[:issue_id])
        if params[:unpin].present?
          BoardArrangement.unpin!(issue)
        else
          move_to_end(issue, params[:column].to_s)
        end
        redirect_to board_path, notice: t("shiplog.admin.board.updated")
      rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
        redirect_to board_path, alert: error.message
      end

      def move_to_end(issue, column)
        raise ArgumentError, "Unknown column: #{column.inspect}" unless Issue::COLUMNS.include?(column)

        ids = Roadmap.new(published_only: false).columns.fetch(column).map { |item| item.issue.id } - [ issue.id ]
        BoardArrangement.new(column:, moved_id: issue.id, issue_ids: ids + [ issue.id ]).save!
      end

      def render_json_error(message)
        render json: { error: message }, status: :unprocessable_content
      end
    end
  end
end
