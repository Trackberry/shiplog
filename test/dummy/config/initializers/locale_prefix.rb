# A stand-in for a host that serves its pages under a locale prefix: /es/changelog renders the changelog with
# I18n.locale = :es, and links keep the prefix (it becomes part of SCRIPT_NAME, as a mount point would be).
# Everything else, the admin included, is untouched. A real host does this with a routes scope or its own
# locale middleware; Shiplog only renders under whatever I18n.locale the host sets.
class LocalePrefix
  PREFIX = %r{\A/es(?=/|\z)}

  def initialize(app) = @app = app

  def call(env)
    return @app.call(env) unless PREFIX.match?(env["PATH_INFO"])

    env = env.merge("SCRIPT_NAME" => "#{env["SCRIPT_NAME"]}/es", "PATH_INFO" => env["PATH_INFO"].sub(PREFIX, "").presence || "/")
    I18n.with_locale(:es) { @app.call(env) }
  end
end

Rails.application.config.middleware.insert_before ActionDispatch::Static, LocalePrefix
