module Shiplog
  module Admin
    module Areas
      # Moves an area one place up or down (params[:direction]); anything else changes nothing.
      class MovesController < ApplicationController
        def create
          Area.find(params[:area_id]).move(params[:direction])
          redirect_to areas_path
        end
      end
    end
  end
end
