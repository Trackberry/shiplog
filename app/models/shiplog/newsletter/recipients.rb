module Shiplog
  module Newsletter
    # The recipients of a newsletter, in batches: the host's users (config.newsletter_recipients, read in batches
    # with find_each when the callable returns a relation) and then the confirmed subscribers. An address with an
    # unsubscribed row (a suppression record, whatever the source of the address) is skipped, one query per
    # batch; so is a duplicate: the first host recipient with an address wins, and a subscriber whose address a
    # host user has is skipped. A host object without a usable email or id (or not responding to email, locale
    # and id) is skipped with a warning that names no address, never a crash.
    class Recipients
      Recipient = Data.define(:key, :email, :locale, :source, :record) do
        def host? = source == :host
        def subscriber? = source == :subscriber
      end

      EMAIL = URI::MailTo::EMAIL_REGEXP

      def initialize(batch_size: Shiplog.config.newsletter_batch_size)
        @batch_size = batch_size
      end

      # Yields Arrays of at most batch_size Recipients (fewer once suppressed and duplicate addresses are dropped).
      def each_batch(&block)
        seen = Set.new
        host_batches { |records| emit(records.filter_map { |record| host_recipient(record) }, seen, suppressed: true, &block) }
        NewsletterSubscriber.confirmed.in_batches(of: @batch_size) do |subscribers|
          emit(subscribers.map { |subscriber| subscriber_recipient(subscriber) }, seen, suppressed: false, &block)
        end
      end

      # Yields each Recipient once, host users first.
      def each(&block) = each_batch { |batch| batch.each(&block) }

      # { "en" => 120, "es" => 30 }: how many recipients get each locale's email, after deduplication.
      def counts_by_locale
        counts = Hash.new(0)
        each { |recipient| counts[recipient.locale] += 1 }
        counts.sort_by { |locale, _| locale }.to_h
      end

      private

      # Yields the candidates that are neither suppressed (checked in one query when `suppressed`; the confirmed
      # subscribers' scope rules it out already) nor seen before.
      def emit(candidates, seen, suppressed:)
        skipped = suppressed ? suppressed_emails(candidates.map(&:email)) : Set.new
        batch = candidates.select { |recipient| !skipped.include?(recipient.email) && seen.add?(recipient.email) }
        yield batch if batch.any?
      end

      # The addresses among `emails` that unsubscribed (NewsletterSubscriber.suppress), lowercased.
      def suppressed_emails(emails)
        return Set.new if emails.empty?

        NewsletterSubscriber.unsubscribed.where("lower(email) IN (?)", emails).pluck(:email).map(&:downcase).to_set
      end

      # The host's recipient objects, batch_size at a time (a relation is read with find_each).
      def host_batches(&block)
        callable = Shiplog.config.newsletter_recipients
        return unless callable

        records = callable.call
        return if records.nil?

        if records.respond_to?(:find_each)
          records.find_each(batch_size: @batch_size).each_slice(@batch_size, &block)
        else
          records.each_slice(@batch_size, &block)
        end
      end

      def host_recipient(record)
        return skip("#{record.class.name}, which does not respond to email, locale and id") unless %i[email locale id].all? { |name| record.respond_to?(name) }
        return skip("a #{record.class.name} without an id") if record.id.blank?

        email = record.email.to_s.strip.downcase
        return if email.empty? || !EMAIL.match?(email) || email.length > NewsletterSubscriber::EMAIL_MAX_LENGTH

        Recipient.new(key: "#{record.class.name}/#{record.id}", email:, locale: Newsletter.locale_for(record.locale), source: :host, record:)
      end

      def subscriber_recipient(subscriber)
        Recipient.new(key: subscriber.recipient_key, email: subscriber.email, locale: Newsletter.locale_for(subscriber.locale), source: :subscriber, record: subscriber)
      end

      def skip(what)
        Rails.logger.warn("[shiplog] newsletter_recipients gave #{what}: skipped")
        nil
      end
    end
  end
end
