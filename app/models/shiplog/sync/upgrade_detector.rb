require "bundler"

module Shiplog
  module Sync
    # Finds the tracked gems (config.repositories `gem:`) that a merged pull request upgraded, by diffing the
    # lockfile at the pull request's base and merge commits, and stores the gem's own pull requests between the
    # two versions in PullRequestUpgrade. A pull request is inspected once: `upgrades_checked_at` marks it.
    class UpgradeDetector
      # The most pull requests inspected per call, so a first backfill does not fetch thousands of lockfiles;
      # the rest are picked up by the following syncs (newest first).
      MAX_PER_CALL = 50
      MAX_CHANGES = 50
      EXCERPT_CHARS = 300
      COMMIT_BATCH = 100

      def initialize(repository, client: Github::Client.new)
        @repository = repository
        @client = client
        @owner, @name = repository.full_name.split("/", 2)
        @config = Shiplog.config
      end

      # Returns the number of pull requests inspected.
      def call
        return 0 unless @config.changelog_repository?(@repository.full_name) && tracked_gems.any?

        pending = @repository.pull_requests.awaiting_upgrade_check.limit(MAX_PER_CALL).to_a
        pending.each { |pull_request| inspect_pull_request(pull_request) }
        pending.size
      end

      private

      def tracked_gems = @tracked_gems ||= @config.tracked_gems

      def inspect_pull_request(pull_request)
        upgrades = detect(pull_request)
        ActiveRecord::Base.transaction do
          upgrades.each { |upgrade| store(pull_request, upgrade) }
          pull_request.update!(upgrades_checked_at: Time.current)
        end
      rescue Github::RateLimited, Github::Transient
        raise
      rescue Github::Error => error
        # Marked as checked anyway: a permanent failure must not keep taking one of the limited slots.
        Rails.logger.warn("[shiplog] Could not inspect #{@repository.full_name}##{pull_request.number} for gem upgrades: #{error.message}")
        pull_request.update!(upgrades_checked_at: Time.current)
      end

      def detect(pull_request)
        return [] if pull_request.base_oid.blank? || pull_request.merge_oid.blank?

        before = locked_gems(pull_request.base_oid)
        after = locked_gems(pull_request.merge_oid)
        return [] if before.nil? || after.nil?

        tracked_gems.filter_map do |gem_name, gem_repository|
          old_gem, new_gem = before[gem_name], after[gem_name]
          next unless old_gem && new_gem && old_gem != new_gem

          resolve(gem_name, gem_repository, old_gem, new_gem)
        end
      end

      # { gem name => { version:, revision: } } from the lockfile at a commit, or nil when it is missing.
      def locked_gems(oid)
        data = @client.query(Github::Queries::BLOB_TEXT, owner: @owner, name: @name, expression: "#{oid}:#{@config.lockfile_path}")
        blob = data.dig("repository", "object")
        text = blob&.fetch("text", nil)
        return if text.blank? || blob["isTruncated"]

        Bundler::LockfileParser.new(text).specs.each_with_object({}) do |spec, gems|
          next unless tracked_gems.key?(spec.name)

          revision = spec.source.options["revision"] if spec.source.is_a?(Bundler::Source::Git)
          gems[spec.name] ||= { version: spec.version.to_s, revision: }
        end
      end

      def resolve(gem_name, gem_repository, old_gem, new_gem)
        upgrade = { gem_name:, gem_repository:, from_ref: old_gem[:version], to_ref: new_gem[:version], changes: [] }
        ref_pairs(old_gem, new_gem).each do |from, to|
          commits = compare(gem_repository, from, to) or next
          return upgrade.merge(from_ref: from, to_ref: to, changes: pull_requests_for(gem_repository, commits))
        end
        Rails.logger.warn("[shiplog] Could not resolve #{gem_name} #{old_gem[:version]} -> #{new_gem[:version]} in #{gem_repository} " \
          "(tag not found or repository not accessible); recording the upgrade without changes")
        upgrade
      end

      # A git source is pinned by revision; a version tries the tag "v<version>", then "<version>".
      def ref_pairs(old_gem, new_gem)
        old_refs, new_refs = candidates(old_gem), candidates(new_gem)
        Array.new([ old_refs.size, new_refs.size ].max) { |i| [ old_refs[[ i, old_refs.size - 1 ].min], new_refs[[ i, new_refs.size - 1 ].min] ] }.uniq
      end

      def candidates(locked) = locked[:revision] ? [ locked[:revision] ] : [ "v#{locked[:version]}", locked[:version] ]

      def compare(gem_repository, from, to)
        escape = ERB::Util.method(:url_encode)
        @client.get("/repos/#{gem_repository}/compare/#{escape.(from)}...#{escape.(to)}").fetch("commits")
      rescue Github::NotFound
        nil
      end

      def pull_requests_for(gem_repository, commits)
        ids = commits.filter_map { |commit| commit["node_id"] }
        found = ids.each_slice(COMMIT_BATCH).flat_map do |batch|
          @client.query(Github::Queries::COMMIT_PULL_REQUESTS, ids: batch)["nodes"].to_a.compact.flat_map do |commit|
            commit.dig("associatedPullRequests", "nodes").to_a.compact
          end
        end
        found.select { |node| node["state"] == "MERGED" && node.dig("repository", "nameWithOwner").to_s.casecmp?(gem_repository) }
          .uniq { |node| node["number"] }.sort_by { |node| node["number"] }.first(MAX_CHANGES)
          .map { |node| { number: node["number"], title: node["title"], body_excerpt: node["body"].to_s.squish.truncate(EXCERPT_CHARS), url: node["url"] } }
      end

      def store(pull_request, upgrade)
        record = pull_request.upgrades.create_or_find_by!(gem_name: upgrade[:gem_name])
        record.update!(from_ref: upgrade[:from_ref], to_ref: upgrade[:to_ref], gem_repository: upgrade[:gem_repository], gem_changes: upgrade[:changes])
      end
    end
  end
end
