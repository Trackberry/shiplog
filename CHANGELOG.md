# Changelog

## 0.2.0 (2026-10-26)

### Added

- A Roadmap / Changelog switcher in the default page header. Add your own pages with `config.extra_pages` (`[{ label:, path: }]`, each a String or a callable evaluated in the view), and render the same switcher on host pages with `helper Shiplog::SwitcherHelper` and `shiplog_switcher`.
- Roadmap status by default: a rule and marker per column, a card tag with the issue's repository (`config.repository_labels`), "Includes N parts" on cards, a "Recently shipped" section (`config.roadmap_shipped_count`, default 4, `0` hides it) and an optional footnote with a "Suggest a feature" link (`shiplog.roadmap.footnote`, `config.feedback_path`).
- New `config.classes` keys: `switcher`, `switcher_link`, `column_marker`, `card_meta`, `card_tag`, `shipped`, `shipped_title`, `shipped_list`, `shipped_item`, `shipped_date`, `shipped_link`, `footnote`, `footnote_link`.
- Per-repository options in `config.repositories`: `{ name:, changelog: false, gem: }`. `changelog: false` keeps a repository on the roadmap only. `gem:` names the gem in your lockfile so that upgrading it produces a single changelog entry, written from the gem's own merged pull requests, instead of one entry per repository. `config.lockfile_path` changes the lockfile that is read.
- `config.cache_version`, to refresh cached public pages when the output of a configured callable changes.
- A Discard button on draft rows of the admin inbox, next to Edit and Approve. It updates the list in place; give a reason from the entry's page.

### Changed

- Roadmap drafts are shorter (about two sentences) and lead with what the customer gets, instead of opening with "We're working on".
- The roadmap's ETag also covers its recently shipped entries and each card's repository and sub-issues, so those changes reach cached pages.
- The migration `create_shiplog_pull_request_upgrades` also adds an index on `shiplog_entries (status, released_on)`.

### Fixed

- The public pages' ETag used a per-process `Hash#hash`, so workers of a multi-process host answered with different ETags for the same page. It is now a stable digest.

### Upgrade notes

- Copy and run the new migration: `bin/rails shiplog:install:migrations`, then `bin/rails db:migrate`.
- The default `shiplog/_page_header` now renders the switcher. Hosts that override `_page_header` keep theirs; render `shiplog_switcher` (or the `shiplog/switcher` partial) in it to get the links.
- If your app overrides `roadmaps/show`, `_column` or `_card` only to add column status, card tags or recently shipped, delete them and use the new defaults and `config.classes` keys.
- Style the new elements with the new class keys above if you use `config.classes` with `config.stylesheet = false`.
- A relative String path such as `"news"` in `extra_pages` now raises `ArgumentError`; use `"/news"`, an `http(s)://` URL or `mailto:`. A `feedback_path` that is not one of these renders no link.
- Repository names are validated: anything other than `owner/name` raises `ArgumentError` when `config.repositories` is assigned.
- For gem upgrades the GitHub token needs read access to **Contents** and **Pull requests** on the gem repositories. Only pull requests synced by 0.2.0 or later are inspected; earlier merges are not backfilled.

## 0.1.1 (2026-10-26)

### Added

- Approve, discard and restore update the inbox in place, without a reload. Without JavaScript they still redirect back to the same filtered list.
- Admins can switch a changelog entry between New feature and Improvement.

### Fixed

- Pull requests whose title starts with a topic (`Importers: …`) are no longer mistaken for a non-changelog Conventional Commits type and skipped; only known types such as `chore:` or `ci:` are.
- Roadmap drafts are written in the future tense ("You'll be able to…") instead of as if the feature had already shipped, and no longer turn implementation details from the issue into promises such as dates, prices, refunds or limits.
- Host layouts can render records that the host app routes, such as Active Storage avatars passed to `image_tag`, `link_to` or `url_for`, inside Shiplog's public and admin pages instead of raising `Can't resolve image into URL`.
- Admin actions return to the filtered list they started from: approving, discarding, restoring or saving an entry keeps the status, kind and page of the inbox.
- The roadmap board's drag and drop keeps working after Turbo Drive navigation in host apps that use it.

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
