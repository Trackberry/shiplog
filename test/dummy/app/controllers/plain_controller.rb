# A host page that does not include any Shiplog helper, in a layout that calls shiplog_head_tags.
class PlainController < ApplicationController
  layout "head_helper"

  def show; end
end
