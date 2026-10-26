# Changelog

## 0.3.0 (unreleased)

### Added

- Entry permalinks: every approved feature and change has a page at `/changelog/:slug`, with a "Back to the changelog" link to its month, and links to the newer and older entries. The changelog list links each title to it. The slug is made from the title when the entry is first approved (`a-z`, `0-9` and dashes only, at most 80 characters, `-2`, `-3` for duplicates, `entry-<id>` when the title leaves nothing) and never changes afterwards. Drafts, discarded and roadmap entries and unknown slugs answer 404. The page sets `content_for :title`, `:shiplog_description` and `:shiplog_og` (Open Graph `og:title`, `og:description`, `og:type`, `og:url`); Shiplog's layout renders them, host layouts should too (see the README). The entry markup is the new `shiplog/changelogs/_entry_content` partial.
- An Atom feed of the latest 50 features and changes at `/changelog.atom`, with stable tag-URI ids, absolute URLs, an ETag, a `<link rel="alternate">` through `content_for :shiplog_feed` and a "Subscribe (Atom)" link on the changelog.
- `Shiplog.unseen_count(since:)` (approved features and changes approved after `since`, all of them when nil, at most 99), the `Shiplog::UnseenHelper#shiplog_unseen_count(since)` view helper, and `config.on_changelog_seen = ->(controller) { ... }`, called before each changelog index or permalink view renders (also when the answer is a 304), so a badge in the same response is current. It may write, so keep it cheap (the README shows a write guard). Shiplog doesn't know your users, so the host supplies and stores the time.
- `config.canonical_url` (nil by default): the origin (`"https://trackberry.com"`) used for the feed's ids, links and the other absolute URLs instead of the request's host. It and `config.product_name` are part of the pages' ETag.
- An unknown permalink slug answers 404 with `X-Cascade: pass`, so host routes declared after the engine mount below the changelog path (`/changelog/archive`) are no longer shadowed.
- `config.changelog_path` is validated leniently: surrounding slashes are stripped (`"/changelog"` works as before), segments may use `a-z`, `0-9`, `-` and `_` and may be nested (`"docs/whats_new"`). Blank values and anything unsafe (spaces, dots, `?`, `#`, uppercase) raise `ArgumentError`.
- `bin/rails shiplog:backfill_slugs`, which gives entries approved before 0.3.0 their permalink slug. The 0.3.0 migration already runs the same generation for every approved feature and change (oldest first), so the task is only needed for entries approved by older code during a deploy window. The public pages never write (a GET may hit a read replica): an approved entry without a slug is listed without a link and has no permalink page until the task runs.
- New `config.classes` keys: `permalink`, `permalink_back`, `permalink_nav`, `permalink_nav_link`. The Atom link reuses `footnote` and `footnote_link` (`shiplog-footnote__link--feed`).
- Product areas, detected by AI. The rewriter's reply may include `"area"`: an existing area (matched ignoring case, then by slug) or a new name of 1-3 words, created while fewer than `config.max_areas` (default 8) exist and the name is valid (at most 40 characters; letters, digits, spaces, `&`, `-`). The prompt lists the existing areas; a reply without `area`, or with a name that can't be used (cap reached, invalid), keeps the entry's current area. An area an admin chose on the entry edit page (`area_set_by_admin`) is never changed by a rewrite or by detection.
- An admin Areas page (in the nav): areas with their entry counts, rename (the slug follows), move up/down, merge (moves the entries, deletes the source) and delete (entries get no area), and a "Detect areas" button that enqueues `Shiplog::DetectAreasJob`. With no areas the job asks your `config.rewriter` to propose up to `max_areas` from up to 200 approved titles, then classifies the entries without an area in batches of 50 titles (at most 20 batches a run, idempotent, logged). The entry edit page gets an Area select (with "None") and the inbox shows an area badge.
- Area detection stamps every entry it asked the AI about (`area_detected_at`), so entries the AI declines are not asked again and later runs reach the rest; the Areas page has a "Re-check unplaced entries" checkbox to ask again. Only one detection runs at a time (a Postgres advisory lock).
- Area slugs for names that `parameterize` empties (Cyrillic, CJK) are the lowercased letters and digits joined by dashes (`Оплата` is `оплата`; `?area=` takes it URL-encoded). Area creation checks `config.max_areas` under a Postgres advisory lock, so concurrent rewrites cannot exceed it. Merging and deleting an area bump the entries' `updated_at`.
- The Areas page shows "Last detection: <time>, assigned N" or the last error. `Shiplog::DetectAreasJob` never retries or raises: failures are logged and recorded, and the Detect button refuses to enqueue without `config.rewriter`.
- On the public changelog, an area filter (`?area=slug`, an "All" link) when at least 2 areas have published entries; it combines with search and pagination and is part of the ETag. An unknown slug answers 404. Entries show their area as a tag (list and permalink), and the Atom feed adds `<category term="slug" label="Name"/>` and honours `?area=`.
- New `config.classes` keys: `areas`, `area_link` (with a `--current` modifier) and `entry_area`; new `config.max_areas`.

### Changed

- The changelog's entry markup moved to `shiplog/changelogs/_entry_content.html.erb`; entry titles on the list are now links.

### Upgrade notes

- Copy and run the new migration: `bin/rails shiplog:install:migrations`, then `bin/rails db:migrate`. It adds `shiplog_entries.slug` (unique index on non-null values), an index on `shiplog_entries (status, approved_at)`, the `shiplog_areas` table and `shiplog_entries.area_id` (nullable foreign key, `ON DELETE SET NULL`, indexed) `shiplog_entries.area_set_by_admin` (boolean, default false) and `shiplog_entries.area_detected_at` (datetime), and the small key-value table `shiplog_settings` (the last area detection's result). The migration also gives the entries approved so far their slug. If old code approves entries during your deploy window, run `bin/rails shiplog:backfill_slugs` afterwards.
- `config.changelog_path` now raises `ArgumentError` for blank values and for characters outside `a-z`, `0-9`, `-`, `_` and `/` (spaces, dots, `?`, `#`, uppercase). Surrounding slashes are stripped, so `"/changelog"` and `"whats_new"` from a 0.2.0 initializer keep working.
- If you override `shiplog/changelogs/_entry.html.erb`, titles are not links in your copy; render `shiplog/changelogs/_entry_content` (locals `entry:`, `heading:`, `linked: true`) or link `changelog_entry_path(entry.slug)` yourself.
- If your `config.public_layout` is your own layout, render `content_for(:shiplog_og)`, `content_for(:shiplog_feed)` and the `:shiplog_description` meta tag in its `<head>` to get Open Graph tags and feed discovery on the permalink pages.
- New I18n keys, all with English defaults: `shiplog.permalink.title`, `.back`, `.nav_label`, `.newer`, `.older` (with `title`); `shiplog.feed.title_with_product` (with `product`), `.link_title`, `.subscribe`.
- Areas appear as you rewrite entries. To fill in existing ones, open the admin's Areas page and click "Detect areas" (it needs `config.rewriter`). Set `config.max_areas` to change the cap of 8 (`0` stops the AI creating areas).
- If you use a custom `config.prompt_builder`, ask your model for `"area"` in its JSON reply, or entries get no area from rewrites.
- If you override `shiplog/changelogs/_entry_content.html.erb` or `show.html.erb`, add the area tag (`entry.area`, class `entry_area`) and render `shiplog/changelogs/_areas` (locals `areas:`, `current:`, `query:`) to get the tag and the filter. The search partial reads the selected area from `@area` (its locals are still `query:` and `count:`, so a 0.2.0 copy keeps rendering, but its form and "Clear search" link don't carry the area: add `<input type="hidden" name="area" value="<%= @area.slug %>">` when `@area` is set, and `area: @area&.slug` to the clear link).
- New I18n keys, all with English defaults: `shiplog.changelog.areas.label` and `.all`; `shiplog.admin.areas.*`, `shiplog.admin.nav.areas`, `shiplog.admin.entries.no_area` and `shiplog.admin.entries.fields.area`.
- Every translation key of the public pages now has an English default (including `shiplog.roadmap.title` and `.lede`, `shiplog.changelog.title`, `.lede` and `.pagination.*`, `shiplog.columns.*`, `shiplog.empty`), so a host locale without Shiplog translations shows English instead of translation-missing spans.
- Style the permalink page with the new class keys above if you use `config.classes` with `config.stylesheet = false`.
- If your layout shows the unseen count, it renders per-user content: declare `etag { current_user&.changelog_seen_at }` on your `public_parent_controller`.

## 0.2.0 (2026-10-26)

### Added

- A Roadmap / Changelog switcher in the default page header. Add your own pages with `config.extra_pages` (`[{ label:, path: }]`, each a String or a callable evaluated in the view), and render the same switcher on host pages with `helper Shiplog::SwitcherHelper` and `shiplog_switcher`.
- Roadmap status by default: a rule and marker per column, a card tag with the issue's repository (`config.repository_labels`), "Includes N parts" on cards, a "Recently shipped" section (`config.roadmap_shipped_count`, default 4, `0` hides it) and an optional footnote with a "Suggest a feature" link (`shiplog.roadmap.footnote`, `config.feedback_path`).
- New `config.classes` keys: `switcher`, `switcher_link`, `column_marker`, `card_meta`, `card_tag`, `shipped`, `shipped_title`, `shipped_list`, `shipped_item`, `shipped_date`, `shipped_link`, `footnote`, `footnote_link`.
- Per-repository options in `config.repositories`: `{ name:, changelog: false, gem: }`. `changelog: false` keeps a repository on the roadmap only. `gem:` names the gem in your lockfile so that upgrading it produces a single changelog entry, written from the gem's own merged pull requests, instead of one entry per repository. `config.lockfile_path` changes the lockfile that is read.
- A Dependabot author, a `chore(deps)` title or the `dependencies` label no longer excludes a pull request that carries gem changes; other excluded labels, such as `internal`, still do.
- `config.cache_version`, to refresh cached public pages when the output of a configured callable changes.
- Search on the public changelog: a GET form (`/changelog?q=csv`) that lists approved features and changes whose title or body contain every word of the query, with a result count, a "Clear search" link and pagination that keeps `q`. Turn it off with `config.changelog_search = false`; override `shiplog/changelogs/_search.html.erb` to change it. New `config.classes` keys: `search`, `search_input`, `search_button`, `search_summary`, `search_clear`, `search_empty`. Search pages set `content_for :shiplog_robots, "noindex"` (emitted as a robots meta tag by Shiplog's own layout; add it to your layout, see the README).
- A Discard button on draft rows of the admin inbox, next to Edit and Approve. It updates the list in place; give a reason from the entry's page.

### Changed

- Roadmap drafts are shorter (about two sentences) and lead with what the customer gets, instead of opening with "We're working on".
- The roadmap's ETag also covers its recently shipped entries and each card's repository and sub-issues, so those changes reach cached pages.
- The migration `create_shiplog_pull_request_upgrades` also adds an index on `shiplog_entries (status, released_on)`.
- Gem upgrade detection: a failure on one pull request no longer blocks the others or keeps the scan window from advancing. Temporary GitHub errors are retried and given up after three attempts; other errors give up at once, with a warning. Pull requests merged before the next scan's start are marked checked without being fetched.
- Only the last commit's lockfile change is seen for a rebase merge; Dependabot's single-commit pull requests are unaffected.

### Fixed

- The scan window could move back to the oldest pending lockfile pull request after a first sync of a long history, drafting every old pull request and commit in that span. It now never ends before its start.
- Hosts that mount the engine with another name (`as: :updates`) no longer get a `NameError` from the switcher.
- The public pages' ETag used a per-process `Hash#hash`, so workers of a multi-process host answered with different ETags for the same page. It is now a stable digest.

### Upgrade notes

- Copy and run the new migration: `bin/rails shiplog:install:migrations`, then `bin/rails db:migrate`. Run it before the job workers start on the new code, because the importer writes the new columns.
- New I18n keys, all with English defaults, so a locale without translations shows English: `shiplog.switcher.label`, `.roadmap`, `.changelog`; `shiplog.roadmap.parts` (with `count`), `.shipped_heading`, `.shipped_date_format`, `.full_changelog`, `.suggest`; `shiplog.changelog.search.label`, `.submit`, `.summary` (with `count` and `query`), `.clear`, `.empty` (with `query`).
- The default `shiplog/_page_header` now renders the switcher. Hosts that override `_page_header` keep theirs; render `shiplog_switcher` (or the `shiplog/switcher` partial) in it to get the links.
- If your app overrides `roadmaps/show`, `_column` or `_card` only to add column status, card tags or recently shipped, delete them and use the new defaults and `config.classes` keys.
- Style the new elements with the new class keys above if you use `config.classes` with `config.stylesheet = false`.
- `extra_pages` paths must be absolute (`/…`), `http(s)://` or `mailto:`. A `feedback_path` that is not one of these renders no link.
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
