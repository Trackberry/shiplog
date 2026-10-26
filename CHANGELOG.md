# Changelog

## 0.1.0 (2026-10-26)

Initial release.

- Public roadmap and changelog engine (`Shiplog::Engine`) and a separate admin engine (`Shiplog::Admin::Engine`) with a drafts inbox, entry editing, a roadmap board with drag and drop, and sync status.
- GitHub GraphQL sync across several repositories, a signed webhook endpoint (`issues`, `pull_request`, `sub_issues`), and scheduled jobs (`Shiplog::SyncJob`, `Shiplog::ScanChangesJob`).
- Roadmap columns derived from GitHub state (open PR or assignee, milestone or `soon` label), with admins able to pin a card to a column.
- Changelog drafts for shipped features (from the issue form's Problem / Before / After) and for small merged PRs and commits, skipping bots, internal conventional-commit types and excluded labels.
- Host-supplied LLM rewriter. Nothing is public until approved, and approved text is never silently replaced.
- Styling: `config.classes` (per-element classes next to stable `shiplog-*` BEM classes), `config.stylesheet`, and a bundled stylesheet in `@layer shiplog` with `--shiplog-*` variables. Public views are split into overridable partials.
- Rendering inside host layouts: `public_parent_controller` / `public_layout`, `admin_parent_controller` / `admin_layout` / `admin_chrome` / `admin_flash`, and unknown `*_path` / `*_url` helpers forwarded to `main_app`.
- Admin access fails closed (`config.authorize_admin` defaults to deny).
- `rails generate shiplog:install` (with `--tailwind`) and a `shiplog-feature.yml` issue form.
