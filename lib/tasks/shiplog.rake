namespace :shiplog do
  desc "Give approved changelog entries that have no permalink slug one (entries approved by code older than 0.3.0 after the migration ran)"
  task backfill_slugs: :environment do
    count = Shiplog::Entry.backfill_slugs
    puts "Shiplog: gave #{count} #{count == 1 ? "entry" : "entries"} a slug."
  end
end
