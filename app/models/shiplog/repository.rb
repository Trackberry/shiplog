module Shiplog
  class Repository < ApplicationRecord
    has_many :issues, dependent: :destroy
    has_many :pull_requests, dependent: :destroy
    has_many :commits, dependent: :destroy

    validates :full_name, presence: true, uniqueness: true
  end
end
