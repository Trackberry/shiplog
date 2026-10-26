# A host page that renders Shiplog's switcher (the News page of a host with extra_pages).
class PagesController < ApplicationController
  helper Shiplog::SwitcherHelper
  helper Shiplog::HeadHelper

  def news; end
end
