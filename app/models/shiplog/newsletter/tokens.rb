module Shiplog
  module Newsletter
    # The tokens in newsletter links: encrypted and signed (AES-256-GCM through ActiveSupport::MessageEncryptor,
    # URL-safe, JSON), keyed from the host's secret_key_base, each with its own purpose so one cannot stand in for
    # another. Nothing in a token is readable without the key (no id, no address in clear in logs or caches); a
    # tampered or expired token decrypts to nil.
    #   confirmation(subscriber)  the double opt-in link: the row's single-use confirmation_nonce, valid
    #                             CONFIRMATION_VALIDITY; the nonce is cleared when the link is used or the address
    #                             unsubscribes, so an old link confirms nothing
    #   unsubscribe(email)        the one-click and footer unsubscribe link: the address, encrypted, so the host's
    #                             users need no row in Shiplog; it does not expire (footers live long)
    # The preferences page uses the subscriber's stored token instead (NewsletterSubscriber#token), rotated after
    # each change made there.
    #
    # Rotating secret_key_base: call `Shiplog::Newsletter::Tokens.rotate(old_secret_key_base)` in an initializer
    # while old unsubscribe links must keep working (they are decrypted with the old key too).
    module Tokens
      CONFIRMATION_VALIDITY = 7.days
      SALT = "shiplog newsletter".freeze
      KEY_LENGTH = 32

      # The confirmation link's token, or nil when the row has no pending confirmation.
      def self.confirmation(subscriber)
        nonce = subscriber.confirmation_nonce
        encryptor.encrypt_and_sign({ "nonce" => nonce }, purpose: :confirm, expires_in: CONFIRMATION_VALIDITY) if nonce.present?
      end

      # The subscriber whose pending confirmation this token is, or nil (tampered, expired, used, or unsubscribed since).
      def self.subscriber_for(token)
        data = read(token, :confirm)
        nonce = data["nonce"] if data.is_a?(Hash)
        NewsletterSubscriber.find_by(confirmation_nonce: nonce) if nonce.is_a?(String) && nonce.present?
      end

      def self.unsubscribe(email) = encryptor.encrypt_and_sign({ "email" => email.to_s.strip.downcase }, purpose: :unsubscribe)

      # The address of an unsubscribe token, or nil when it does not verify.
      def self.email_for(token)
        data = read(token, :unsubscribe)
        data["email"].presence if data.is_a?(Hash) && data["email"].is_a?(String)
      end

      # Adds a previous secret_key_base whose tokens must still be accepted.
      def self.rotate(secret_key_base)
        previous_secrets << secret_key_base.to_s
        @encryptor = nil
      end

      def self.reset_rotation!
        previous_secrets.clear
        @encryptor = nil
      end

      def self.previous_secrets = (@previous_secrets ||= [])

      def self.encryptor
        @encryptor ||= ActiveSupport::MessageEncryptor.new(Rails.application.key_generator.generate_key(SALT, KEY_LENGTH), url_safe: true, serializer: JSON).tap do |encryptor|
          previous_secrets.each { |secret| encryptor.rotate(key_generator(secret).generate_key(SALT, KEY_LENGTH)) }
        end
      end

      def self.key_generator(secret)
        ActiveSupport::KeyGenerator.new(secret, iterations: 1000, hash_digest_class: ActiveSupport::KeyGenerator.hash_digest_class)
      end
      private_class_method :key_generator

      def self.read(token, purpose)
        return if token.blank?

        encryptor.decrypt_and_verify(token.to_s, purpose:)
      rescue ActiveSupport::MessageEncryptor::InvalidMessage, ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
        nil
      end
      private_class_method :read
    end
  end
end
