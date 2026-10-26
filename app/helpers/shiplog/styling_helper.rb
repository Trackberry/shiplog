module Shiplog
  module StylingHelper
    # The stable BEM class of an element, BEM modifiers (class--modifier) and the host's classes
    # from config.classes[key]. Unknown keys raise outside production so typos surface early.
    def shiplog_class(key, *modifiers)
      key = key.to_sym
      base = Shiplog::Classes::BEM[key]
      if base.nil?
        raise ArgumentError, "Unknown Shiplog class key #{key.inspect}. Valid keys: #{Shiplog::Classes::KEYS.join(", ")}" unless Rails.env.production?
        return shiplog_host_classes(key)
      end

      bem = [ base, *modifiers.compact.map { |modifier| "#{base}--#{modifier.to_s.dasherize}" } ]
      [ *bem, shiplog_host_classes(key) ].compact_blank.join(" ")
    end

    private

    def shiplog_host_classes(key)
      configured = Shiplog.config.classes
      Array(configured[key] || configured[key.to_s]).join(" ").squish.presence
    end
  end
end
