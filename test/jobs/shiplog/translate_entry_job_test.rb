require "test_helper"

class Shiplog::TranslateEntryJobTest < ActiveJob::TestCase
  setup do
    @calls = 0
    Shiplog.config.locales = [ :es ]
    Shiplog.config.rewriter = lambda do |_prompt|
      @calls += 1
      '{"title":"Modo oscuro","body":"Texto"}'
    end
    @entry = shiplog_entries(:dark_mode_feature)
  end

  test "translates the entry into the locale" do
    Shiplog::TranslateEntryJob.perform_now(@entry, :es)

    assert_equal "Modo oscuro", @entry.translations.find_by!(locale: "es").title
  end

  test "takes the locale as a String too" do
    Shiplog::TranslateEntryJob.perform_now(@entry, "es")

    assert_equal 1, @entry.translations.count
  end

  test "a second run for the same English text makes no LLM call" do
    2.times { Shiplog::TranslateEntryJob.perform_now(@entry, :es) }

    assert_equal 1, @calls
  end

  test "force translates again" do
    Shiplog::TranslateEntryJob.perform_now(@entry, :es)
    Shiplog::TranslateEntryJob.perform_now(@entry, :es, force: true)

    assert_equal 2, @calls
  end

  test "does nothing for an entry that is not approved" do
    draft = shiplog_entries(:csv_change_draft)
    Shiplog::TranslateEntryJob.perform_now(draft, :es)

    assert_equal 0, @calls
    assert_equal 0, draft.translations.count
  end

  test "does nothing without a rewriter" do
    Shiplog.config.rewriter = nil

    assert_nothing_raised { Shiplog::TranslateEntryJob.perform_now(@entry, :es) }
    assert_equal 0, @entry.translations.count
  end

  test "retries a failing rewriter a bounded number of times, logs, then gives up without raising" do
    Shiplog.config.rewriter = lambda do |_prompt|
      @calls += 1
      raise "LLM down"
    end
    log = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(log)

    perform_enqueued_jobs { Shiplog::TranslateEntryJob.perform_later(@entry, :es) }

    assert_equal 3, @calls
    assert_equal 0, @entry.translations.count
    assert_equal 3, log.string.scan("LLM down").size.clamp(0, 3)
    assert_match(/Giving up translating entry #{@entry.id} into es/, log.string)
  ensure
    Rails.logger = original
  end

  test "an invalid reply is retried the same bounded way" do
    Shiplog.config.rewriter = lambda do |_prompt|
      @calls += 1
      "not json"
    end

    perform_enqueued_jobs { Shiplog::TranslateEntryJob.perform_later(@entry, :es) }

    assert_equal 3, @calls
  end

  test "a job for a deleted entry is dropped" do
    Shiplog::TranslateEntryJob.perform_later(@entry, :es)
    Shiplog::Entry.where(id: @entry.id).delete_all

    assert_nothing_raised { perform_enqueued_jobs }
    assert_equal 0, @calls
  end
end
