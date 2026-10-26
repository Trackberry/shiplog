# Run in a separate process by test/integration/early_action_view_boot_test.rb. Boots the dummy app with a host
# initializer that loads ActionView::Base (as `ActionView::Base.field_error_proc = ...` in config/initializers
# does) before the autoloaders are set up, then reports what shiplog_head_tags does. Prints one JSON line.
ENV["RAILS_ENV"] = "test"
require "json"
require "rack/mock"
require_relative "../dummy/config/application"

Shiplog::Application.initializer "host.touches_action_view_early" do
  ActionView::Base.field_error_proc = proc { |html_tag, _instance| html_tag }
end

Rails.application.initialize!

host_view = ApplicationController.new.view_context
host_page = Rack::MockRequest.new(Rails.application).get("/news")
# Autoloaded constants that haven't been loaded yet still have an autoload registered.
public_controller_loaded_by_host_page = Shiplog.autoload?(:PublicController).nil?
page = Rack::MockRequest.new(Rails.application).get("/changelog")

puts JSON.generate(
  helper_owner: ActionView::Base.instance_method(:shiplog_head_tags).owner.name,
  host_page: host_view.shiplog_head_tags,
  host_page_status: host_page.status,
  public_controller_loaded_by_host_page:,
  status: page.status,
  canonical: page.body[%r{<link rel="canonical" href="([^"]+)"}, 1]
)
