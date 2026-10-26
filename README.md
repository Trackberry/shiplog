# Shiplog

A mountable Rails engine that turns your GitHub issues, pull requests and commits into a public roadmap and changelog written for customers, not developers. An LLM that you supply drafts the plain-language text. Nothing is public until an admin approves it.

- **Roadmap**: issues labelled `public` appear in three columns (In progress, Coming soon, Later) once approved.
- **Changelog**: shipped features and small changes, grouped by month.
- **Admin**: drafts inbox, entry editing, a drag-and-drop roadmap board and a sync status page.

## Requirements

- Ruby 4.0 or newer
- Rails 8.1.4 or newer (< 9)
- PostgreSQL (tables use `jsonb`)
- A job backend for Active Job (GoodJob, Solid Queue, ...)

## Installation

```ruby
# Gemfile
gem "shiplog"
```

```sh
bundle install
bin/rails generate shiplog:install
bin/rails db:migrate
```

The generator:

- creates `config/initializers/shiplog.rb` with every setting, commented;
- adds the public mount (and a commented admin mount) to `config/routes.rb`;
- runs `shiplog:install:migrations` (all tables are prefixed `shiplog_`);
- copies the issue form to `.github/ISSUE_TEMPLATE/shiplog-feature.yml`. It has Problem / Before / After fields and applies the `public` label.

With `--tailwind` the initializer also sets `config.stylesheet = false` and a `config.classes` hash of Tailwind classes, and the generator adds the `@source` line to `app/assets/tailwind/application.css`. See [Styling](#styling).

## Mounting

Shiplog ships two engines so that the admin can sit behind your own authentication while the public pages and the GitHub webhook stay open (the same approach as GoodJob):

```ruby
# config/routes.rb
mount Shiplog::Engine => "/"   # /roadmap, /changelog, /shiplog/github/webhook, engine assets

authenticate :user, ->(user) { user.admin? } do   # Devise shown; use whatever fits your app
  mount Shiplog::Admin::Engine => "/admin/shiplog"
end
```

The generator writes the admin mount as a comment because authentication differs between apps. Uncomment it once it is wrapped in a constraint.

`config.authorize_admin` is checked by the admin controllers and a falsy result returns 403. It is fail-closed: the default denies everyone, so a mount that is not configured is never open. The generated initializer sets `config.authorize_admin = ->(controller) { true }` because the route constraint around the mount does the authentication. If you do not wrap the mount in a constraint, replace it with a real check (for example `controller.current_user&.admin?`).

The public paths come from `config.roadmap_path` and `config.changelog_path`, read when routes are drawn.

### Customising the admin layout

By default the admin uses its own layout (`layouts/shiplog/admin`) and its own CSS and JS, served by the engine (and aware of your CSP nonce). To change it, create the same file in your app, which takes precedence over the engine's:

```erb
<%# app/views/layouts/shiplog/admin.html.erb %>
```

To render the admin inside your own admin layout instead, see [Rendering inside your layouts](#rendering-inside-your-layouts).

For smaller tweaks override a partial instead:

- `app/views/shiplog/admin/_custom_head.html.erb`: rendered inside `<head>` of the engine layout (extra stylesheets, favicon, ...).
- `app/views/shiplog/admin/_nav.html.erb`: the navigation bar (a compact sub-nav when a host layout is used).
- `app/views/shiplog/admin/_assets.html.erb`: links `admin.css`; every admin page renders it, so it works in any layout.

Engine views use the engine's route helpers, so inside a host layout or partial rendered by a Shiplog controller your own routes are available as `main_app.` helpers, or directly (see [host route helpers](#host-route-helpers)).

### Public pages

The public controllers inherit from `config.public_parent_controller` and render with `config.public_layout`.

## Configuration

All settings live in `config/initializers/shiplog.rb`:

| Key | Default | Description |
|---|---|---|
| `repositories` | `[]` | GitHub repositories to sync, as `"owner/name"`. Sub-issues may cross repositories of the same owner. |
| `github_token` | `nil` | A String, or a callable evaluated on every GitHub request. |
| `webhook_secret` | `nil` | Secret of the GitHub webhook. While blank, the webhook endpoint answers 503. |
| `public_label` | `"public"` | Only issues with this label reach the roadmap. |
| `soon_labels` | `["soon"]` | Labels that put an issue in "Coming soon". A milestone does the same. |
| `excluded_labels` | `["internal", "dependencies", "refactor", "chore"]` | Pull requests with one of these labels never become changelog entries. |
| `excluded_authors` | `[/\[bot\]\z/]` | Patterns (matched with `===`) for authors whose pull requests and commits are skipped. |
| `commit_types` | `["feat", "fix", "perf"]` | Conventional-commit types eligible for the changelog. Commits need one of these types; pull requests whose title has a different type (`ci:`, `chore(deps):`, ...) are skipped, untyped titles are kept. |
| `rewriter` | `nil` | Callable that rewrites text with an LLM. See [The rewriter](#the-rewriter). |
| `product_name` | `nil` | Your product's name, used in the prompts. |
| `audience` | `nil` | Who your customers are, used in the prompts. |
| `tone` | `"Friendly, concise, no jargon. Address the customer as 'you'."` | Writing style used in the prompts. |
| `prompt_builder` | `nil` | Optional `->(kind:, context:) { String }` replacing the built-in prompts. `kind` is `"roadmap"`, `"feature"` or `"change"`. |
| `public_parent_controller` | `"ActionController::Base"` | Parent class of the public controllers. Read once when they load, so set it in the initializer. |
| `public_layout` | `"shiplog/application"` | Layout of the public pages. |
| `admin_parent_controller` | `"ActionController::Base"` | Parent class of the admin controllers. Read once when they load, so set it in the initializer. |
| `admin_layout` | `"shiplog/admin"` | Layout of the admin pages. |
| `admin_chrome` | `:standalone` | `:standalone` wraps the admin in Shiplog's own page chrome (nav bar, flash, background). `:hosted` is for an `admin_layout` of your own: Shiplog renders only a compact sub-nav inside your content. Anything else raises `ArgumentError`. The layout name is never inspected. |
| `admin_flash` | `true` | In `:hosted` mode, render Shiplog's flash messages inside the admin content. Set to `false` if your layout already shows the flash. Standalone always shows it. |
| `stylesheet` | `true` | Include the bundled `shiplog.css` in the public pages. Set to `false` when you style them yourself. |
| `classes` | `{}` | Extra classes per element, added to the stable `shiplog-*` classes. See [Styling](#styling). |
| `authorize_admin` | `->(controller) { false }` | Admin check; return false for a 403. Denies everyone until set; the generated initializer opens it, relying on your route constraint. |
| `current_admin` | `->(controller) { controller.try(:current_user)&.try(:email) }` | Stored as the approver of an entry. |
| `roadmap_path` | `"roadmap"` | Path of the public roadmap. |
| `changelog_path` | `"changelog"` | Path of the public changelog. |

Example:

```ruby
Shiplog.configure do |config|
  config.repositories   = %w[acme/app acme/app-ios]
  config.github_token   = -> { Rails.application.credentials.dig(:github, :shiplog_token) }
  config.webhook_secret = Rails.application.credentials.dig(:github, :shiplog_webhook_secret)
  config.product_name   = "Acme"
  config.audience       = "small business owners who invoice customers"
  config.rewriter       = ->(prompt) { RubyLLM.chat.ask(prompt).content }
end
```

## GitHub token

Shiplog talks to the GitHub GraphQL API. Provide either:

- a **fine-grained personal access token** with access to the configured repositories and read-only permissions for **Issues**, **Pull requests**, **Contents** and **Metadata**; or
- a **GitHub App installation token** with the same permissions. Because `github_token` accepts a callable, you can mint a fresh token on each call:

```ruby
config.github_token = -> { MyApp::GithubApp.installation_token }
```

## Webhook setup

Webhooks keep Shiplog fresh between scheduled syncs. In each repository (or at organisation level) add a webhook:

- **Payload URL**: `https://your-app.example.com/shiplog/github/webhook` (prefix it if you mounted `Shiplog::Engine` below `/`)
- **Content type**: `application/json`
- **Secret**: the value of `config.webhook_secret`
- **Events**: *Issues*, *Pull requests* and *Sub-issues*

Requests are verified with `X-Hub-Signature-256`; an invalid signature returns 401. Each `X-GitHub-Delivery` id is recorded, so redeliveries are harmless. Valid events enqueue a `Shiplog::RefreshJob` that refetches the current state of the issue or pull request and respond 202. `ping` answers 200 and other events are ignored. Recent deliveries are listed on the admin Sync page.

## Scheduling

Webhooks can be missed, so schedule two jobs:

- `Shiplog::SyncJob`: reconciles issues and pull requests and creates missing drafts. Every 30 minutes is a good start. The first run backfills everything.
- `Shiplog::ScanChangesJob`: looks at default-branch commits without a pull request, then drafts small changes. Run it weekly.

GoodJob (`config/initializers/good_job.rb` or `config/application.rb`):

```ruby
config.good_job.enable_cron = true
config.good_job.cron = {
  shiplog_sync: { cron: "*/30 * * * *", class: "Shiplog::SyncJob" },
  shiplog_scan_changes: { cron: "0 6 * * 1", class: "Shiplog::ScanChangesJob" }
}
```

Solid Queue (`config/recurring.yml`):

```yaml
production:
  shiplog_sync:
    class: Shiplog::SyncJob
    schedule: every 30 minutes
  shiplog_scan_changes:
    class: Shiplog::ScanChangesJob
    schedule: every monday at 6am
```

You can also trigger a sync from the admin Sync page. Rewriting always runs in `Shiplog::RewriteEntryJob`, never in a request.

## The rewriter

`config.rewriter` is a callable that receives the prompt (a String) and returns a String containing a JSON object:

```json
{"title": "...", "body": "...", "customer_facing": true}
```

Shiplog extracts the first valid JSON object from the reply, so models that wrap it in prose or code fences still work. `customer_facing: false` means the model thinks the change is irrelevant for customers; such small changes are stored as discarded and can be restored by an admin. If no rewriter is configured, the reply can't be parsed or the call raises, the entry keeps the original GitHub text and the error is shown in the admin, where you can edit the text or regenerate.

With [RubyLLM](https://rubyllm.com):

```ruby
config.rewriter = ->(prompt) { RubyLLM.chat.ask(prompt).content }
```

With the Anthropic SDK:

```ruby
client = Anthropic::Client.new
config.rewriter = lambda do |prompt|
  message = client.messages.create(model: "claude-sonnet-5-5", max_tokens: 1024, messages: [ { role: "user", content: prompt } ])
  message.content.first.text
end
```

## How items reach the roadmap

- An issue is *public* when it has `config.public_label`.
- A public, open issue whose parent is not itself public is a roadmap item. Public children of a public parent are folded into the parent.
- A roadmap item is drafted, rewritten and visible on `/roadmap` only after an admin approves it. It leaves the roadmap when it is closed.
- The column is the first match of:
  1. the column an admin pinned it to;
  2. **In progress**: the issue or one of its sub-issues has an open linked pull request, or the issue has assignees;
  3. **Coming soon**: it has a milestone or a label from `soon_labels`;
  4. **Later**.
- Within a column cards are ordered by their board position, then by last GitHub update. Dragging a card on the admin board pins it to the target column and stores the order. "Unpin" returns it to the automatic column. Without JavaScript, each card has a column select and a Move button.

## How changelog entries are produced

- **Features**: a public top-level issue closed as completed that has at least one merged linked pull request on itself or a sub-issue. The issue form sections (`### Problem`, `### Before`, `### After`), sub-issue titles and linked pull request titles are given to the rewriter. Only issues closed in the last 90 days are drafted, so a first sync doesn't flood the inbox. The release date is the newest merge date.
- **Small changes**: the weekly scan looks at pull requests merged, and stored commits made, since the last scan (seven days on the first run). Commits are only considered when they are on the default branch and have no pull request, and their conventional-commit type (`feat:`, `fix(scope):`, ...) must be in `commit_types`. Pull requests are skipped when their title carries a type outside `commit_types`; untyped titles are left for the rewriter to judge. Bot authors are recorded as `name[bot]`, so the default `excluded_authors` pattern matches them.
- **Exclusions**: pull requests with an excluded label or an excluded author, commits from excluded authors, pull requests that belong to a feature's issue tree (the feature entry covers them), and anything that already has an entry.

## Approval workflow

Every entry starts as a **draft**. In the admin inbox you can edit the text, regenerate it, approve it or discard it. Only approved entries are public. Discarded entries are never proposed again but can be restored. If the GitHub text changes after a draft was written, the entry is flagged "GitHub text changed since this draft" and can be regenerated, and approved text is never replaced silently.

Approved changelog entries do not react to later GitHub changes (a reverted pull request, a removed label): discard them by hand in the admin. A roadmap issue that is re-labelled or reopened shows its previously approved text again, and the inbox flags it as "GitHub text changed". Issues deleted or transferred on GitHub are closed locally (state reason `deleted`), which removes them from the roadmap; their entries are kept.

Drafts whose rewrite job was lost (no result and no error after an hour) are queued again by the next sync, and the admin marks them "Not rewritten yet" until then.

## Styling

The public pages ship plain semantic HTML with stable [BEM](https://getbem.com) classes (`shiplog-card`, `shiplog-entry__title`, ...) and a small, framework-free stylesheet. Pick the level that fits your app; the same views work in all of them.

### 1. CSS variables

The bundled stylesheet is driven by variables you can set on `:root`, `body` or `.shiplog-page`. Inside your own layout it inherits your text colour and draws cards and borders as translucent mixes of that colour (`color-mix` against `currentColor`), so it works on light and dark hosts without any setting. Only Shiplog's own layout (`.shiplog-layout`), which paints the page background, switches to dark colours with `prefers-color-scheme`.

| Variable | Meaning |
|---|---|
| `--shiplog-fg` | Text colour |
| `--shiplog-muted` | Secondary text |
| `--shiplog-bg` | Page background (only painted by the engine's own layout) |
| `--shiplog-card` | Card and entry background |
| `--shiplog-border` | Borders and dividers |
| `--shiplog-accent` | Links, feature marker, pill, hover |
| `--shiplog-radius` | Corner radius (default `0.5rem`) |
| `--shiplog-font` | Font family |
| `--shiplog-space` | Base spacing unit (default `1rem`) |

```css
:root { --shiplog-accent: #7c3aed; --shiplog-radius: 0.75rem; }
```

### 2. Override the BEM classes

All rules live in `@layer shiplog`, so any unlayered CSS in your app wins without extra specificity:

```css
.shiplog-card { border-radius: 0; }
.shiplog-entry--feature { border-left-width: 8px; }
```

If your own CSS is layered too, declare the order up front, for example `@layer shiplog, app;`.

### 3. `config.classes` (Tailwind and other utility frameworks)

`config.classes` maps a key to the classes added to that element, next to its BEM class. Set `config.stylesheet = false` to drop the bundled CSS:

```ruby
Shiplog.configure do |config|
  config.stylesheet = false
  config.classes = {
    columns: "grid gap-6 md:grid-cols-3",
    card: "rounded-lg border border-gray-200 bg-white p-3 dark:border-gray-800 dark:bg-gray-900"
  }
end
```

With Tailwind v4, the class names live in a Ruby file, so tell Tailwind to scan it. In `app/assets/tailwind/application.css`:

```css
@import "tailwindcss";
@source "../../../config/initializers/shiplog.rb";
```

(The path is relative to the stylesheet: `app/assets/tailwind/` up three levels is the app root.) `bin/rails generate shiplog:install --tailwind` writes both for you, with neutral gray/indigo classes covering every key.

If you keep the bundled stylesheet (`stylesheet: true`) next to Tailwind v4 utilities, declare the layer order before the import so utilities win over Shiplog's rules:

```css
@layer theme, base, shiplog, components, utilities;
@import "tailwindcss";
@source "../../../config/initializers/shiplog.rb";
```

Without it, `shiplog` is first seen when `shiplog.css` loads, which can put it after `utilities` in the cascade order (a layer's position is fixed by its first mention), and then `.shiplog-card { border-radius: ... }` would beat a `rounded-lg` utility. Declaring the order first pins `shiplog` below `components` and `utilities`.

| Key | BEM class | Element |
|---|---|---|
| `page` | `shiplog-page` (+ `--roadmap` / `--changelog`) | Page wrapper |
| `page_header` | `shiplog-page__header` | Header with title and lede |
| `page_title` | `shiplog-page__title` | `h1` |
| `page_lede` | `shiplog-page__lede` | Intro paragraph |
| `columns` | `shiplog-columns` | Roadmap column grid |
| `column` | `shiplog-column` (+ `--in-progress` / `--coming-soon` / `--later`) | One roadmap column |
| `column_header` | `shiplog-column__header` | Column heading block |
| `column_title` | `shiplog-column__title` | Column `h2` |
| `column_count` | `shiplog-column__count` | Number of items |
| `column_description` | `shiplog-column__description` | One-line description |
| `column_empty` | `shiplog-column__empty` | Empty column notice |
| `cards` | `shiplog-cards` | List of roadmap cards |
| `card` | `shiplog-card` | Roadmap card |
| `card_title` | `shiplog-card__title` | Card `h3` |
| `card_body` | `shiplog-card__body` | Card text |
| `months` | `shiplog-months` | Changelog months wrapper |
| `month` | `shiplog-month` | One month section |
| `month_title` | `shiplog-month__title` | Month `h2` |
| `entries` | `shiplog-entries` | List of entries |
| `entry` | `shiplog-entry` (+ `--feature` / `--change`) | Changelog entry |
| `entry_feature` | `shiplog-entry--feature` | Also applied to feature entries |
| `entry_category` | `shiplog-entry__category` | "New" / "Improved" pill |
| `entry_title` | `shiplog-entry__title` | Entry `h3` |
| `entry_body` | `shiplog-entry__body` | Entry text |
| `entry_date` | `shiplog-entry__date` | `time` element |
| `pagination` | `shiplog-pagination` | Pagination `nav` |
| `pagination_link` | `shiplog-pagination__link` (+ `--newer` / `--older`) | Newer/older links |
| `empty` | `shiplog-empty` | "Nothing here yet" notice |

Values may be strings or arrays. The list is `Shiplog::Classes::KEYS`; in development and test, `shiplog_class` raises `ArgumentError` for any other key. Texts come from I18n (`shiplog.roadmap.title`, `shiplog.roadmap.lede`, `shiplog.changelog.*`, `shiplog.categories.feature` / `change`, `shiplog.columns.<column>_description`), so override them in your locale files.

### 4. Override the partials

Copy any view from the engine's `app/views/shiplog/` into your app with the same path and edit it. Each partial documents its locals in a comment on its first lines:

- `shiplog/_page.html.erb`, `shiplog/_page_header.html.erb`, `shiplog/_pagination.html.erb`, `shiplog/_empty.html.erb`
- `shiplog/roadmaps/_column.html.erb`, `shiplog/roadmaps/_card.html.erb`
- `shiplog/changelogs/_month.html.erb`, `shiplog/changelogs/_entry.html.erb`

`shiplog/_page.html.erb` is what links the stylesheet (so it also works in layouts you don't control); keep that line if you copy it and still want the bundled CSS.

The admin has its own stylesheet, scoped under `.shiplog-admin` and also in `@layer shiplog`. Its variables (`--shiplog-admin-fg`, `-muted`, `-bg`, `-surface`, `-border`, `-accent`) can be set on `:root` or `.shiplog-admin`. The admin follows the same rule: dark colours only in the standalone chrome, inherited colours when `admin_chrome` is `:hosted`.

## Rendering inside your layouts

- **Public pages**: set `config.public_parent_controller` (default `ActionController::Base`; read once when the controller loads, so use the initializer) and `config.public_layout` (default `"shiplog/application"`). The public controllers run under the parent's `before_action`s, so pick one that lets visitors through.
- **Admin**: set `config.admin_parent_controller` (same rule), `config.admin_layout` and `config.admin_chrome = :hosted`. Each admin page links its own `admin.css` (and `board.js` on the board) and wraps itself in `<div class="shiplog-admin">`, so nothing depends on your layout's `<head>`. In `:hosted` mode Shiplog adds a small Drafts / Roadmap board / Sync sub-nav inside the content and shows its flash messages there too (set `config.admin_flash = false` if your layout renders the flash itself). The board reads the CSRF token from `meta[name=csrf-token]` and falls back to a `data-csrf-token` attribute, so your layout does not need `csrf_meta_tags` for drag and drop.
- `config.authorize_admin` and the route constraint still apply.

### Host route helpers

A layout rendered by a Shiplog controller runs in the engine's isolated routing context. Shiplog's controllers include `Shiplog::HostRoutesHelper`, which forwards any `*_path` / `*_url` helper the engine does not define to `main_app`, so `root_path`, `about_path` or `new_user_session_path` work in your layout as they do elsewhere. Helpers the engine defines win: in the public engine `roadmap_path` is Shiplog's, and in the admin engine `root_path` is the admin root, so use `main_app.root_path` there when you mean your own.

### Example: Trackberry-style setup

```ruby
# config/routes.rb
mount Shiplog::Engine => "/"                       # /roadmap and /changelog next to the app's own pages
authenticate :user, ->(user) { user.admin? } do
  mount Shiplog::Admin::Engine => "/admin/shiplog"
end

# config/initializers/shiplog.rb
Shiplog.configure do |config|
  config.public_parent_controller = "ApplicationController"
  config.public_layout            = "application"
  config.admin_parent_controller  = "Admin::BaseController"
  config.admin_layout             = "admin"
  config.admin_chrome             = :hosted
  config.stylesheet               = false
  config.classes                  = { columns: "grid gap-6 md:grid-cols-3", card: "rounded-lg border p-3" } # see the generator for all keys
end
```

The host layouts keep using their own helpers (`root_path`, `current_user`, ...) and Tailwind compiles the classes through the `@source` line.

## Hosting notes

- Set `public_parent_controller` and `admin_parent_controller` in an initializer (`config/initializers/shiplog.rb`). They are read once, when the engine's controller classes load, so changing them later has no effect.
- The public pages send an ETag covering the data, locale, gem version, `config.classes` and `config.stylesheet`. If your host layout shows per-user content, declare `etag { current_user&.id }` in the parent controller (`config.public_parent_controller`); Rails ETags are inherited, so cached responses are not shared between users.

## Running the tests

```sh
bin/rails db:create db:schema:load   # once, creates shiplog_test on local PostgreSQL
bin/rails test
bin/rubocop
```

The database is configured in `test/dummy/config/database.yml`; set `PGHOST`, `PGUSER` and `PGPASSWORD` if your PostgreSQL needs them.

Tests that call the real GitHub API are skipped by default. To run them:

```sh
SHIPLOG_LIVE_GITHUB=1 GITHUB_TOKEN=... SHIPLOG_LIVE_REPO=owner/name bin/rails test test/live
```

`SHIPLOG_LIVE_REPO` defaults to `Trackberry/shiplog`.

## License

Released under the [MIT License](MIT-LICENSE).
