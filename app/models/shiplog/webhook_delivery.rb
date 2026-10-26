module Shiplog
  class WebhookDelivery < ApplicationRecord
    validates :delivery_id, presence: true, uniqueness: true
  end
end
