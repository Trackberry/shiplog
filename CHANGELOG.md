# Changelog

## Unreleased

- Styling API: `config.classes` (per-element classes next to stable `shiplog-*` BEM classes, via `shiplog_class`), `config.stylesheet` and a bundled stylesheet rewritten as `@layer shiplog` with `--shiplog-*` variables.
- Public views split into partials (`shiplog/_page_header`, `roadmaps/_column`, `roadmaps/_card`, `changelogs/_month`, `changelogs/_entry`, `_pagination`, `_empty`). Roadmap columns show a count and a description; changelog entries show a date and a New/Improved pill. The public layout no longer links the stylesheet: the page does.
- Host layouts: unknown `*_path`/`*_url` helpers are forwarded to `main_app`; `config.admin_parent_controller` and `config.admin_layout` render the admin inside a host layout. The admin stylesheet is scoped under `.shiplog-admin`.
- `rails generate shiplog:install --tailwind`.

## 0.1.0

Initial release.

- Public roadmap and changelog engine, plus an admin engine with drafts inbox, entry editing, roadmap board with drag and drop, and sync status.
- GitHub GraphQL sync, webhook endpoint and scheduled jobs (`Shiplog::SyncJob`, `Shiplog::ScanChangesJob`).
- Host-supplied LLM rewriter; nothing is public until approved.
- `rails generate shiplog:install` and a `shiplog-feature.yml` issue form.
