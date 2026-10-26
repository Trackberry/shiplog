Rails.application.routes.draw do
  mount Shiplog::Engine => "/"
  mount Shiplog::Admin::Engine => "/admin/shiplog"
end
