# Shiplog::Engine and Shiplog::Admin::Engine share the gem's root, so Rails loads this file once for each: the
# guard keeps every task from running twice.
unless Rake::Task.task_defined?("shiplog:backfill_slugs")
  namespace :shiplog do
    desc "Give approved changelog entries that have no permalink slug one (entries approved by code older than 0.3.0 after the migration ran)"
    task backfill_slugs: :environment do
      count = Shiplog::Entry.backfill_slugs
      puts "Shiplog: gave #{count} #{count == 1 ? "entry" : "entries"} a slug."
    end

    desc "Draft the announcement of a month (MONTH=2026-10; the previous month by default) and queue its rewrite"
    task draft_announcement: :environment do
      month = ENV["MONTH"].present? ? Date.strptime(ENV["MONTH"], "%Y-%m") : Date.current.prev_month
      entry = Shiplog::Announcements.draft(month:)
      label = month.strftime("%Y-%m")
      if entry
        puts "Shiplog: drafted the #{label} announcement (entry #{entry.id})."
      elsif !Shiplog.announcements?
        puts "Shiplog: config.announcements is false, nothing drafted."
      else
        puts "Shiplog: nothing drafted for #{label}: it has an announcement already, or no approved feature or change."
      end
    rescue Date::Error
      abort "Shiplog: MONTH must look like 2026-10, got #{ENV["MONTH"].inspect}."
    end

    desc "Delete the newsletter subscribers who never confirmed within 30 days and the delivery rows older than 180 days (what Shiplog::PurgeNewsletterJob does)"
    task purge_newsletter: :environment do
      counts = Shiplog::PurgeNewsletterJob.perform_now
      puts "Shiplog: purged #{counts[:subscribers]} unconfirmed newsletter #{counts[:subscribers] == 1 ? "subscriber" : "subscribers"} and #{counts[:deliveries]} old delivery #{counts[:deliveries] == 1 ? "row" : "rows"}."
    end

    desc "Translate approved entries and area names that have no current translation into config.locales (entries approved before 0.3.0 get none). BATCH_SIZE=100"
    task translate_approved: :environment do
      if Shiplog.config.locales.empty?
        puts "Shiplog: config.locales is empty, nothing to translate."
      elsif Shiplog.config.rewriter.nil?
        puts "Shiplog: config.rewriter is not set, so nothing can be translated."
      else
        result = Shiplog::Entry.enqueue_missing_translations(batch_size: ENV.fetch("BATCH_SIZE", 100).to_i.clamp(1, 10_000))
        approved = result[:approved]
        puts "Shiplog: #{approved} approved #{approved == 1 ? "entry" : "entries"}."
        result[:enqueued].each do |locale, count|
          puts "Shiplog: #{locale}: #{count} enqueued, #{approved - count} current."
        end
        areas = Shiplog::Area.enqueue_missing_translations
        puts "Shiplog: #{areas} #{areas == 1 ? "area" : "areas"} enqueued for name translation."
      end
    end
  end
end
