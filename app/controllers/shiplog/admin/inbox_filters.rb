module Shiplog
  module Admin
    # The drafts inbox state (status, kind, page) carried through every action that leaves the list, so
    # the admin lands back on the same filtered list. Values are rebuilt from a whitelist and never taken
    # from a URL or the Referer, so they cannot be used for an open redirect.
    module InboxFilters
      extend ActiveSupport::Concern

      MAX_PAGE = 100_000

      included do
        helper_method :inbox_filter_params
      end

      # Only present, valid values: { status:, kind:, page: } with any unknown or invalid key dropped.
      def inbox_filter_params
        @inbox_filter_params ||= { status: inbox_status, kind: inbox_kind, page: inbox_page }.compact
      end

      private
        # Inline (script) requests get the re-rendered row; plain requests redirect back to the filtered list.
        def respond_inline(entry, message_key)
          message = t("shiplog.admin.entries.#{message_key}")
          return redirect_to(root_path(inbox_filter_params), notice: message) unless request.format.json?

          render json: { row: render_inbox_row(entry), matches_filter: inbox_match?(entry), message: message }
        end

        def respond_inline_error(message, fallback)
          return render(json: { error: message }, status: :unprocessable_content) if request.format.json?

          redirect_to fallback, alert: message
        end

        def render_inbox_row(entry)
          render_to_string(partial: "shiplog/admin/entries/entry_row", formats: :html, locals: { entry: })
        end

        # Mirrors EntriesController#index: drafts unless a status was given, any kind unless one was.
        def inbox_match?(entry)
          entry.status == (inbox_filter_params[:status] || "draft") &&
            (inbox_filter_params[:kind].nil? || entry.kind == inbox_filter_params[:kind])
        end

        def inbox_status = Entry.statuses.key(params[:status].to_s) && params[:status].to_s

        def inbox_kind = Entry.kinds.key(params[:kind].to_s) && params[:kind].to_s

        def inbox_page
          page = Integer(params[:page].to_s, 10, exception: false)
          page.clamp(1, MAX_PAGE) if page&.positive?
        end
    end
  end
end
