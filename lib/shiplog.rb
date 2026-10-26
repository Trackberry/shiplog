require "shiplog/version"
require "shiplog/classes"
require "shiplog/configuration"
require "shiplog/github/errors"
require "shiplog/github/queries"
require "shiplog/github/client"
require "shiplog/engine"
require "shiplog/admin/engine"

module Shiplog
  class << self
    def config = (@config ||= Configuration.new)
    def configure = yield(config)
    def reset_config! = (@config = nil)
  end
end
