module Shiplog
  module Admin
    module Entries
      # An announcement's text as a file, for hosts that publish it on their own blog or newsletter tool:
      # ?as=markdown (default), html or text, in the default locale or ?export_locale=<one of config.locales>. The text is
      # the current translation when there is one, else the English text (Entry#to_markdown).
      class ExportsController < ApplicationController
        FORMATS = {
          "markdown" => [ "md", "text/markdown" ],
          "html" => [ "html", "text/html" ],
          "text" => [ "txt", "text/plain" ]
        }.freeze

        def show
          entry = Entry.find(params[:entry_id])
          return head(:not_found) unless entry.announcement?

          locale = export_locale
          return head(:not_found) unless locale

          extension, type = FORMATS.fetch(params[:as].to_s.presence || "markdown") { return head(:not_found) }
          send_data content(entry, extension, locale), type: "#{type}; charset=utf-8", disposition: "attachment",
            filename: "#{entry.slug.presence || "announcement-#{entry.id}"}#{"-#{locale}" unless locale == I18n.default_locale.to_s}.#{extension}"
        end

        private

        # The default locale or a configured one; nil for anything else.
        def export_locale
          requested = params[:export_locale].to_s.presence || I18n.default_locale.to_s
          requested if requested == I18n.default_locale.to_s || Entry.translated_locale?(requested)
        end

        def content(entry, extension, locale)
          title = entry.display_title(locale).to_s
          case extension
          when "md" then "# #{title}\n\n#{entry.to_markdown(locale)}\n"
          when "html" then "<h1>#{ERB::Util.html_escape(title)}</h1>\n#{entry.to_html(locale)}\n"
          else "#{title}\n\n#{entry.to_text(locale)}\n"
          end
        end
      end
    end
  end
end
