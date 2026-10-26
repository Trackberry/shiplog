require "shiplog/version"
require "shiplog/configuration"
require "shiplog/engine"
require "shiplog/admin/engine"

module Shiplog
  class << self
    def config = (@config ||= Configuration.new)
    def configure = yield(config)
    def reset_config! = (@config = nil)
  end
end
