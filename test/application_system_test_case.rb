require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ]

  # Selenium talks to chromedriver and the app server over localhost; GitHub stays blocked.
  setup { WebMock.disable_net_connect!(allow_localhost: true) }
  # As in integration tests: the dummy app stands in for a host that guards the admin mount.
  setup { Shiplog.config.authorize_admin = ->(_controller) { true } }
  teardown { WebMock.disable_net_connect! }
end
