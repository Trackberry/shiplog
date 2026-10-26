module Shiplog
  class PullRequestUpgrade < ApplicationRecord
    belongs_to :pull_request
  end
end
