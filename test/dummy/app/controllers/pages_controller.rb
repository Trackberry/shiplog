# A host page that renders Shiplog's switcher (the News page of a host with extra_pages) and, while the
# newsletter is on, Shiplog's subscribe form.
class PagesController < ApplicationController
  helper Shiplog::SwitcherHelper
  helper Shiplog::NewsletterHelper

  def news; end
end
