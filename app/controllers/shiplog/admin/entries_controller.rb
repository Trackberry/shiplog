module Shiplog
  module Admin
    class EntriesController < ApplicationController
      def index = render(html: "".html_safe, layout: true)
    end
  end
end
