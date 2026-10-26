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
        def inbox_status = Entry.statuses.key(params[:status].to_s) && params[:status].to_s

        def inbox_kind = Entry.kinds.key(params[:kind].to_s) && params[:kind].to_s

        def inbox_page
          page = Integer(params[:page].to_s, 10, exception: false)
          page.clamp(1, MAX_PAGE) if page&.positive?
        end
    end
  end
end
