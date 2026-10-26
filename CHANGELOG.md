# Changelog

## Unreleased

## 0.1.0

Initial release.

- Public roadmap and changelog engine, plus an admin engine with drafts inbox, entry editing, roadmap board with drag and drop, and sync status.
- GitHub GraphQL sync, webhook endpoint and scheduled jobs (`Shiplog::SyncJob`, `Shiplog::ScanChangesJob`).
- Host-supplied LLM rewriter; nothing is public until approved.
- `rails generate shiplog:install` and a `shiplog-feature.yml` issue form.
