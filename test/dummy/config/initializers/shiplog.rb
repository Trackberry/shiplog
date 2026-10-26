# Resolved once, when the admin controllers load: the dummy admin sits under a host base controller.
Shiplog.configure do |config|
  config.admin_parent_controller = "Admin::BaseController"
  # The development server stands in for a host whose route constraint authenticates the admin mount.
  config.authorize_admin = ->(_controller) { true } if Rails.env.development?
end
