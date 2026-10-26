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

  # Runs the block with an extra, otherwise empty locale (a host locale that lacks Rails' date formats).
  # The I18n backend state is restored afterwards.
  def with_extra_locale(locale)
    available = I18n.available_locales
    I18n.available_locales = available + [ locale ]
    I18n.with_locale(locale) { yield }
  ensure
    I18n.available_locales = available
    I18n.backend.reload!
  end

  # Counts statements issued, including ones served by the query cache (which still indicate N+1 patterns),
  # unless ignore_cache: true (then only statements that reached the database count).
  def count_queries(ignore_cache: false)
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) || (ignore_cache && (payload[:cached] || payload[:name] == "CACHE"))
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  # The SQL statements issued inside the block (schema and transaction bookkeeping left out).
  def sql_statements
    statements = []
    collector = ->(_name, _start, _finish, _id, payload) { statements << payload[:sql] unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(collector, "sql.active_record") { yield }
    statements
  end

  def github_fixture(name) = file_fixture("github/#{name}.json").read

  # The bytes of a tiny real image fixture: :png, :jpg, :gif, :webp, or the refused :svg and :html.
  def image_bytes(type) = file_fixture(image_fixture_name(type)).binread

  def image_fixture_name(type) = "images/#{{ svg: "drawing.svg", html: "page.html" }.fetch(type) { "pixel.#{type}" }}"

  # Runs the block as a host without Active Storage would see Shiplog.
  def without_active_storage
    original = Shiplog.method(:active_storage?)
    Shiplog.define_singleton_method(:active_storage?) { false }
    yield
  ensure
    Shiplog.define_singleton_method(:active_storage?, original)
  end

  # An uploaded file for the admin's upload form: one of the image fixtures, or `bytes` with a declared type.
  def image_upload(type, name: nil, bytes: nil, mime: nil)
    extension = { svg: "svg", html: "html" }.fetch(type, type.to_s)
    mime ||= { png: "image/png", jpg: "image/jpeg", gif: "image/gif", webp: "image/webp", svg: "image/svg+xml", html: "text/html" }.fetch(type)
    path = if bytes
      (@upload_tempfiles ||= []) << Tempfile.new([ "upload", ".#{extension}" ], binmode: true).tap { |file| file.write(bytes) && file.flush }
      @upload_tempfiles.last.path
    else
      file_fixture(image_fixture_name(type)).to_s
    end
    Rack::Test::UploadedFile.new(path, mime, true, original_filename: name || "shot.#{extension}")
  end
end
