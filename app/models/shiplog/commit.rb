module Shiplog
  class Commit < ApplicationRecord
    belongs_to :repository
    has_many :entries, as: :subject, dependent: :destroy

    def title = message.lines.first.to_s.strip
    def body = message.lines.drop(1).join.strip
  end
end
