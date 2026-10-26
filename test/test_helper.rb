# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
ActiveRecord::Migrator.migrations_paths << File.expand_path("../db/migrate", __dir__)
require "rails/test_help"

# The admin parent controller is resolved when this class loads. Load it before any test resets the
# configuration that the dummy initializer set.
Shiplog::Admin::ApplicationController

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end

require "webmock/minitest"

class ActionDispatch::IntegrationTest
  # The default is fail-closed; the dummy app stands in for a host that wraps the admin mount in a route constraint.
  setup { Shiplog.config.authorize_admin = ->(_controller) { true } }
end

class ActiveSupport::TestCase
  teardown { Shiplog.reset_config! }

  def with_extra_locale(locale)
    available = I18n.available_locales
    I18n.available_locales = available + [ locale ]
    # An app locale normally gets its date formats from rails-i18n; the dummy has none.
    I18n.backend.store_translations(locale, date: { formats: { long: "%d %B %Y" } })
    I18n.with_locale(locale) { yield }
  ensure
    I18n.available_locales = available
  end

  # Counts statements issued, including ones served by the query cache (which still indicate N+1 patterns).
  def count_queries
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def github_fixture(name) = file_fixture("github/#{name}.json").read
end
