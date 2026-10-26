module Shiplog
  # A host layout rendered by a Shiplog controller runs in the engine's isolated routing context, so
  # the host's own helpers (root_path, new_user_session_path, ...) are undefined there. This forwards
  # any unknown *_path / *_url call to main_app when the host app defines it. Helpers the engine
  # defines itself (roadmap_path, board_path, ...) are real methods and always win.
  #
  # Polymorphic URLs get the same treatment. Rails registers `resolve` mappings (Active Storage's
  # VariantWithRecord, ...) on the host's routes only, so image_tag(record), url_for(record),
  # link_to(label, record) and polymorphic_path/url(record) would otherwise fall through to
  # record.to_model. When the engine has no mapping for the record's class but main_app does, the
  # call is delegated to main_app. Engine mappings keep precedence.
  module HostRoutesHelper
    def method_missing(name, ...)
      if shiplog_host_route?(name)
        main_app.public_send(name, ...)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      shiplog_host_route?(name) || super
    end

    def polymorphic_url(record_or_hash_or_array, options = {})
      return super unless shiplog_host_mapping?(record_or_hash_or_array)

      main_app.polymorphic_url(record_or_hash_or_array, options)
    end

    def polymorphic_path(record_or_hash_or_array, options = {})
      return super unless shiplog_host_mapping?(record_or_hash_or_array)

      main_app.polymorphic_path(record_or_hash_or_array, options)
    end

    def url_for(options = nil)
      return super unless shiplog_host_mapping?(options)

      _generate_paths_by_default ? polymorphic_path(options) : polymorphic_url(options)
    end

    private

    def shiplog_host_mapping?(record)
      return false if record.nil? || record.is_a?(Hash) || record.is_a?(Array) || record.is_a?(String) ||
        record.is_a?(Symbol) || record.is_a?(Class) || record.is_a?(ActionController::Parameters)
      return false unless respond_to?(:main_app, true)

      name = record.respond_to?(:to_model) ? record.to_model.model_name.name : record.class.name
      !_routes.polymorphic_mappings.key?(name) && main_app._routes.polymorphic_mappings.key?(name)
    end

    def shiplog_host_route?(name)
      name.end_with?("_path", "_url") && respond_to?(:main_app, true) && main_app.respond_to?(name)
    end
  end
end
