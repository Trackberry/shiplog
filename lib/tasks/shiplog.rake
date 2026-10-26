namespace :shiplog do
  desc "Give approved changelog entries that have no permalink slug one (entries approved before 0.3.0)"
  task backfill_slugs: :environment do
    count = Shiplog::Entry.backfill_slugs
    puts "Shiplog: gave #{count} #{count == 1 ? "entry" : "entries"} a slug."
  end
end
