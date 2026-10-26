# Shiplog

A mountable Rails engine that turns your GitHub issues, pull requests and commits into a public roadmap and changelog written for customers, not developers. An LLM that you supply drafts the plain-language text. Nothing is public until an admin approves it.

- **Roadmap**: issues labelled `public` appear in three columns (In progress, Coming soon, Later) once approved.
- **Changelog**: shipped features and small changes, grouped by month, each with its own permalink page, plus an Atom feed.
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
| `repositories` | `[]` | GitHub repositories to sync, as `"owner/name"` or a Hash with options. Sub-issues may cross repositories of the same owner. See [Repositories](#repositories). |
| `lockfile_path` | `"Gemfile.lock"` | Lockfile read in merged pull requests to detect [gem upgrades](#gem-upgrades). Change it for a monorepo. |
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
| `public_parent_controller` | `"ActionController::Base"` | Parent class of the public controllers. Read once when they load, so set it in the initializer; assigning it after the controllers loaded raises `ArgumentError`. |
| `public_layout` | `"shiplog/application"` | Layout of the public pages. |
| `admin_parent_controller` | `"ActionController::Base"` | Parent class of the admin controllers. Read once when they load, so set it in the initializer; assigning it after the controllers loaded raises `ArgumentError`. |
| `admin_layout` | `"shiplog/admin"` | Layout of the admin pages. |
| `admin_chrome` | `:standalone` | `:standalone` wraps the admin in Shiplog's own page chrome (nav bar, flash, background). `:hosted` is for an `admin_layout` of your own: Shiplog renders only a compact sub-nav inside your content. Anything else raises `ArgumentError`. The layout name is never inspected. |
| `admin_flash` | `true` | In `:hosted` mode, render Shiplog's flash messages inside the admin content. Set to `false` if your layout already shows the flash. Standalone always shows it. |
| `stylesheet` | `true` | Include the bundled `shiplog.css` in the public pages. Set to `false` when you style them yourself. |
| `classes` | `{}` | Extra classes per element, added to the stable `shiplog-*` classes. See [Styling](#styling). |
| `authorize_admin` | `->(controller) { false }` | Admin check; return false for a 403. Denies everyone until set; the generated initializer opens it, relying on your route constraint. |
| `current_admin` | `->(controller) { controller.try(:current_user)&.try(:email) }` | Stored as the approver of an entry. |
| `roadmap_path` | `"roadmap"` | Path of the public roadmap. |
| `changelog_path` | `"changelog"` | Path of the public changelog: one segment of `a-z`, `0-9` and dashes (no slashes; anything else raises `ArgumentError`). Permalinks live below it and the feed is `<path>.atom`. |
| `canonical_url` | `nil` | The site's canonical origin, e.g. `"https://trackberry.com"`. See [Canonical URL](#canonical-url). |
| `extra_pages` | `[]` | Pages added to the switcher after Roadmap and Changelog: `[{ label:, path: }]`, each a String or a callable evaluated in the view. See [Product updates navigation](#product-updates-navigation). Anything else raises `ArgumentError`. |
| `repository_labels` | `{}` | Tag shown on a roadmap card for the repository of its issue: `{ "owner/name" => "iPhone & iPad" }`. Values are Strings or callables evaluated in the view; repositories without one show no tag. |
| `roadmap_shipped_count` | `4` | How many recently shipped changelog entries (features and changes) the roadmap lists below its columns. `0` hides the section. |
| `cache_version` | `nil` | A String added to the public pages' ETag. Callables (`extra_pages`, `repository_labels`, `feedback_path`) cannot be fingerprinted, so bump it when the output of a callable you configured changes. |
| `feedback_path` | `nil` | Target of the roadmap's "Suggest a feature" link, a String or a callable evaluated in the view. No link while `nil`. |
| `changelog_search` | `true` | Search box on the public changelog and `?q=` filtering. `false` hides the form and ignores `q`. See [Changelog search](#changelog-search). |
| `on_changelog_seen` | `nil` | `->(controller) { ... }` called before each changelog index or permalink view renders (also for a 304 revisit), to stamp a visitor's "last seen" time. See [What's new](#whats-new-the-unseen-count). Anything but `nil` or a callable raises `ArgumentError`. |
| `max_areas` | `8` | How many [product areas](#product-areas) the AI may create. Past it, entries can only join existing areas. A non-negative Integer; `0` stops the AI creating areas. |

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

## Repositories

Each entry of `config.repositories` is a String (`"owner/name"`) or a Hash:

```ruby
config.repositories = [
  "acme/app",
  "acme/app-ios",
  { name: "acme/market_data", changelog: false, gem: "market_data" },
  { name: "acme/produce", changelog: false, gem: "acme-produce" }
]
```

| Option | Default | Description |
|---|---|---|
| `name` | required | `"owner/name"`. |
| `changelog` | `true` | `false` makes the repository roadmap-only: its issues still feed the roadmap, but its pull requests and commits never become changelog entries. |
| `gem` | `nil` | The gem's name in your `Gemfile.lock`, for [gem upgrades](#gem-upgrades). |

Unknown options and invalid values raise `ArgumentError` when you assign `repositories`, and so does a name that is not `owner/name` (letters, digits, `.`, `_` and `-`; a segment cannot be only dots). A repository with both `gem:` and `changelog: true` is accepted, but a warning is logged: its changes would be drafted twice, from its own pull requests and from the upgrade. Set `changelog: false`.

`gem:` must be set explicitly because gem names and repository names differ (`acme-produce` lives in `acme/produce`), and a public gem can share a name with one of your repositories without being it: the `holidays` gem from RubyGems is not `acme/holidays`. Matching on names would attach someone else's changes to your changelog, so only gems listed with `gem:` are tracked.

`config.lockfile_path` (default `"Gemfile.lock"`) is the lockfile Shiplog reads in the repositories where `changelog` is true.

## Gem upgrades

A change made in a gem you depend on should appear in the changelog once, when your customers get it: the day your app upgraded the gem. Shiplog does this with the repositories you listed with `gem:`.

For each merged pull request in a repository with `changelog: true` that changes the lockfile:

1. Shiplog reads the lockfile at the merge commit's first parent and at the merge commit itself, and compares the tracked gems with `Bundler::LockfileParser`.
2. For a gem whose version changed it resolves the tag in the gem's repository (`v<version>` and `<version>`, trying the matching styles first and then the mixed ones). For a git source it uses the locked revision. Shiplog then compares the two refs.
3. It lists the pull requests merged between the two refs (GitHub's compare API, then the pull requests associated with those commits, the newest 50) and stores them with the upgrade.
4. The pull request gets one change draft, dated at its merge. The gem's changes (up to 20 titles with excerpts) go into the rewrite prompt, and the rewriter writes one customer-facing entry, or marks it not customer-facing.

A Dependabot bump, a `chore(deps):` title or the `dependencies` label does not exclude a pull request that carries an upgrade with changes; without one it is skipped as usual. Other excluded labels (such as `internal`) still exclude it. If a tag cannot be found, or the gem's repository is not readable by the token, the upgrade is recorded without changes and a warning is logged; the rewriter then works from the pull request alone.

The GitHub token needs read access to the gem repositories as well (**Contents** and **Pull requests**). Detection is capped per sync (50 pull requests), so a large repository's first sync finishes over several syncs.

Only pull requests synced by 0.2.0 or later are inspected: merges imported earlier are not backfilled, and their gem changes are not turned into entries. Pull requests merged before the next scan's start (the last scan, or seven days ago for a repository never scanned) are marked checked without being fetched, since nothing that old would be drafted. A pull request whose inspection fails with a temporary GitHub error is retried on the next syncs and given up after three attempts; any other error gives it up at once, with a warning.

**Rebase merges.** Shiplog reads the lockfile at the merge commit and at its first parent. For a rebase merge, GitHub creates no merge commit: the pull request's "merge commit" is the last rebased commit, so only that commit's lockfile change is seen. Dependabot's pull requests are a single commit, so they are unaffected; a rebased branch that bumps a gem in an earlier commit is missed.

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
{"title": "...", "body": "...", "customer_facing": true, "area": "Billing"}
```

`area` is optional (see [Product areas](#product-areas)); a reply without it works as before.

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
- **Small changes**: the weekly scan looks at pull requests merged, and stored commits made, since the last scan (seven days on the first run). Commits are only considered when they are on the default branch and have no pull request, and their conventional-commit type (`feat:`, `fix(scope):`, ...) must be in `commit_types`. Pull requests are skipped when their title starts with a Conventional Commits type (`chore:`, `ci:`, `docs:`, ...) outside `commit_types`; a topic prefix such as `Importers:` is not a type; untyped titles are left for the rewriter to judge. Bot authors are recorded as `name[bot]`, so the default `excluded_authors` pattern matches them.
- **Exclusions**: pull requests with an excluded label or an excluded author, commits from excluded authors, pull requests that belong to a feature's issue tree (the feature entry covers them), and anything that already has an entry.

## Approval workflow

Every entry starts as a **draft**. In the admin inbox you can edit the text, regenerate it, approve it or discard it. Only approved entries are public. Discarded entries are never proposed again but can be restored. If the GitHub text changes after a draft was written, the entry is flagged "GitHub text changed since this draft" and can be regenerated, and approved text is never replaced silently.

Approved changelog entries do not react to later GitHub changes (a reverted pull request, a removed label): discard them by hand in the admin. A roadmap issue that is re-labelled or reopened shows its previously approved text again, and the inbox flags it as "GitHub text changed". Issues deleted or transferred on GitHub are closed locally (state reason `deleted`), which removes them from the roadmap; their entries are kept.

Drafts whose rewrite job was lost (no result and no error after an hour) are queued again by the next sync, and the admin marks them "Not rewritten yet" until then.

## Product updates navigation

The default page header shows a switcher under the lede: **Roadmap**, **Changelog**, then `config.extra_pages`. The current page carries `aria-current="page"`: of the pages whose path equals or contains the request path, the one with the longest path is current. Add your own pages, for example a news section:

```ruby
config.extra_pages = [
  { label: "News", path: "/learn/news" },
  # Callables are evaluated in the view, so route helpers and I18n work:
  { label: -> { t("pages.docs") }, path: -> { main_app.docs_path } }
]
```

To show the same switcher on your own pages, add the helper to the controller and call it in the view. It links the stylesheet (unless `config.stylesheet` is `false`) and finds the engine's route proxy in your routes whatever name you gave the mount (`as: :updates`), so it works in main-app views. It raises an error if `Shiplog::Engine` is not mounted:

```ruby
class NewsController < ApplicationController
  helper Shiplog::SwitcherHelper
end
```

```erb
<%= shiplog_switcher %>
```

A `path` String must start with `/` (not `//`, `/\` or `/` followed by whitespace), `http://`, `https://` or `mailto:`, and contain no control characters; anything else, such as `"news"`, raises `ArgumentError` when you assign `extra_pages`. An absolute `http(s)` page is marked current only on its own host (`request.host`). A callable that returns another scheme renders the label as text, without a link, and logs a warning. `feedback_path` follows the same rule at render time: an unsafe value shows no link.

Labels come from `shiplog.switcher.roadmap`, `.changelog` and `.label` (the `nav` label); every Shiplog key has an English default, so a locale without translations shows English. Style it with the `switcher` and `switcher_link` keys of [`config.classes`](#3-configclasses-tailwind-and-other-utility-frameworks); the current link also has `shiplog-switcher__link--current`. Hosts that override `shiplog/_page_header` keep their own header; render `shiplog_switcher` or the `shiplog/switcher` partial in it to get the links.

### Roadmap details

- **Status:** each column has a rule on top and a marker (`shiplog-column__marker--in-progress` / `--coming-soon` / `--later`).
- **Card meta:** the label of the issue's repository (`config.repository_labels`) and "Includes N parts" when the issue has more than one sub-issue (`shiplog.roadmap.parts`). A card with neither has no meta element.
- **Recently shipped:** the last `config.roadmap_shipped_count` approved feature and change entries (default 4), each linking to its month on the changelog, plus a "See the full changelog" link. The roadmap's ETag follows changelog approvals.
- **Footnote:** set the `shiplog.roadmap.footnote` translation (empty by default, nothing renders while it is empty) and `config.feedback_path` for a "Suggest a feature" link (`shiplog.roadmap.suggest`).

## Changelog search

The public changelog has a search form above its months: `GET /changelog?q=csv` lists the approved features and changes whose title or body contain every word of the query (case-insensitive `ILIKE`, so PostgreSQL; `%`, `_` and `\` are matched literally). Only the first 5 words of the first 100 characters count. Results keep the changelog's order and month grouping and are paginated; the pagination links keep `q`. With a query the page shows "N results for “csv”" and a "Clear search" link, or a "no entries match" message. A blank `q` is the same as no `q`. The form is a plain GET form (`role="search"`, a `type="search"` input named `q` with an `aria-label`), so it needs no JavaScript.

- Turn it off with `config.changelog_search = false`: no form, and `q` is ignored.
- Override `shiplog/changelogs/_search.html.erb` (locals `query:` and `count:`, both `nil` without a query) to change the markup. Style it with the `search*` keys of [`config.classes`](#3-configclasses-tailwind-and-other-utility-frameworks).
- Texts: `shiplog.changelog.search.label`, `.submit`, `.summary` (`one` / `other`, with `count` and `query`), `.clear` and `.empty` (with `query`); all have English defaults.
- The ETag includes the normalised query.
- The model scope is `Shiplog::Entry.search(query)`.

**Keeping search pages out of search engines.** A page with a query sets `content_for :shiplog_robots, "noindex"`. Shiplog's own layout turns that into `<meta name="robots" content="noindex">`. A host layout (`config.public_layout`) controls its own `<head>`, so emit it there:

```erb
<%= tag.meta name: "robots", content: content_for(:shiplog_robots) if content_for?(:shiplog_robots) %>
```

## Product areas

The rewriter groups entries into product areas ("Billing", "Reports"), and the changelog lets visitors filter by area.

- **Detection while rewriting.** The prompt lists the existing areas (as data, before the `<source>` block) and asks the model for `"area"` in its JSON reply: an existing name, or a new name of 1-3 words when none fits. Shiplog matches the name against the existing areas ignoring case, then by slug, and creates a new area only while fewer than `config.max_areas` (default 8) exist and the name is valid: at most 40 characters, letters, digits, spaces, `&` and `-`. Anything else leaves the entry without an area. A reply without `"area"` (or with one that is not a String) changes nothing. Roadmap entries get areas too, but only features and changes show them publicly. A custom `config.prompt_builder` builds its own prompt, so it has to ask for `area` itself.
- **Detect areas.** The admin has an Areas page with a "Detect areas" button, which enqueues `Shiplog::DetectAreasJob`. With no areas yet, the job asks your `config.rewriter` (same callable, a dedicated prompt, reply `{"areas": [...]}`) to propose up to `max_areas` areas from the titles of up to 200 approved features and changes. Then it classifies the draft and approved entries that have no area, 50 titles per prompt (reply `{"assignments": [{"id": 1, "area": "Billing"}]}`), using only existing areas; unknown ids and areas are ignored. It is idempotent (it only touches entries without an area), bounded (at most 20 classification prompts, 1000 entries, per run; click again for more) and logs what it did (`[shiplog] Detect areas: ...`). The page shows no job state, only a "Detection queued" flash; refresh to see the result. The titles are sent, never the bodies.
- **Admin.** The Areas page lists areas with their entry counts. You can rename (the slug follows), move up/down, merge into another area (moves the entries, deletes the source) and delete (the entries have no area). The entry edit page has an Area select with "None"; changing it marks the entry as set by an admin (`area_set_by_admin`), and neither rewrites nor detection ever change such an entry's area. The inbox shows the area as a badge.
- **Public.** With at least 2 areas that have published features or changes, the changelog shows an "All" link and one link per area above the list (`?area=slug`, the `areas` / `area_link` keys, `--current` on the selected one). It combines with search and pagination (the links keep both) and is part of the ETag, with the names, slugs and order of all areas. An unknown `?area=` slug answers 404; a blank one is ignored. Every entry shows its area as a tag (`entry_area`), in the list and on the permalink page. The Atom feed adds `<category term="slug" label="Name"/>` to entries with an area and honours `?area=` (404 for an unknown one). Roadmap cards don't change.
- **Texts:** `shiplog.changelog.areas.label` and `.all`, and `shiplog.admin.areas.*`, `shiplog.admin.nav.areas`, `shiplog.admin.entries.no_area` and `.fields.area`; all have English defaults.
- **Schema:** the `shiplog_areas` table (`name`, `slug` unique, `position`) and `shiplog_entries.area_id` (nullable foreign key, `ON DELETE SET NULL`) and `area_set_by_admin`. The cap is checked, not locked: two rewrites racing for the last slot can create one area too many.

## Entry permalinks

Every approved feature and change has its own page at `GET /changelog/:slug` (under `config.changelog_path`). The changelog list links each title to it. Roadmap entries have no permalink.

- **Slug:** made when the entry is first approved, from the title (`parameterize` with underscores turned into dashes, so `a-z`, `0-9` and single dashes only; at most 80 characters, `entry-<id>` when nothing is left) and made unique with `-2`, `-3`, ... A later title edit keeps the slug, so links never break; restoring and re-approving an entry keeps it too. A unique index (partial, on non-null slugs) guards against two approvals racing for one slug, and the loser retries.
- **Entries approved before 0.3.0** get their slug from the 0.3.0 migration (oldest first, so the oldest keeps the plain slug on duplicate titles). `bin/rails shiplog:backfill_slugs` (idempotent, oldest first) does the same for entries that old code approved during a deploy window. The public pages never write, because a host may send GETs to a read replica: an approved entry without a slug is listed without a link, left out of the feed and has no page until it has a slug. An entry whose stored slug the route rejects is treated the same way.
- **The page** shows the entry, a "← Back to the changelog" link to the entry's month anchor, and its newer and older neighbours (`rel="prev"` and `rel="next"`, as in the pagination). Drafts, discarded and roadmap entries and unknown slugs answer 404.
- **Caching:** the ETag covers the entry and its neighbours' ids and `updated_at`.
- **Head tags:** the page sets `content_for :title`, `content_for :shiplog_description` (the body, cut at 160 characters) and `content_for :shiplog_og` (Open Graph: `og:title`, `og:description`, `og:type` = `article`, `og:url`). Shiplog's own layout renders them. A host layout (`config.public_layout`) controls its own `<head>`, so render them there, as for `:shiplog_robots`:

```erb
<title><%= content_for(:title) %></title>
<%= tag.meta name: "description", content: content_for(:shiplog_description) if content_for?(:shiplog_description) %>
<%= content_for(:shiplog_og) %>
<%= content_for(:shiplog_feed) %>
```

- **Styling:** the `permalink` (the `article`), `permalink_back`, `permalink_nav` and `permalink_nav_link` keys of [`config.classes`](#3-configclasses-tailwind-and-other-utility-frameworks). Override `shiplog/changelogs/_entry_content.html.erb` (locals `entry:`, `heading:`, `linked:`) to change what an entry shows in both the list and the permalink page.
- **Texts:** `shiplog.permalink.title`, `.back`, `.nav_label`, `.newer` and `.older` (with `title`); all have English defaults.

## Atom feed

`GET /changelog.atom` serves the latest 50 approved features and changes (newest first) as an Atom feed. An entry has a stable id (a tag URI built from the permalink path, so a title edit does not change it), its permalink, `published` (the release date), `updated`, and its body as HTML. All URLs are absolute. The feed is cached with an ETag like the pages and answers 304 on a match; it does not call `on_changelog_seen`.

The changelog and permalink pages advertise it with a `<link rel="alternate" type="application/atom+xml">` (`content_for :shiplog_feed`, rendered by Shiplog's layout; render it in a host layout too, see above) and the changelog shows a visible "Subscribe (Atom)" link (the `footnote_link` key). The feed has an `<author>` (the product name, or "Changelog"), which RFC 4287 requires when entries carry none. The feed is titled "Changelog", or "<product_name> changelog" when `config.product_name` is set, and follows the request locale. Texts: `shiplog.feed.title_with_product`, `.link_title` and `.subscribe`.

### Canonical URL

By default the feed's ids and every absolute URL (the feed's self and alternate links, entry links, `og:url`, the feed discovery link) are built from the request's host, which varies: apex and `www`, or a forged `X-Forwarded-Host`. A feed reader treats a changed id as a new entry, so set the origin once:

```ruby
config.canonical_url = "https://trackberry.com"
```

It must be an `http(s)` origin: scheme, host and an optional port, no path, query or credentials (a trailing slash is dropped; anything else raises `ArgumentError`). A path prefix is not needed: if you mount the engine under one (`mount Shiplog::Engine => "/updates"`), the routes already add it, so the feed lives at `https://trackberry.com/updates/changelog.atom`. The feed's tag URIs use the canonical host. It is part of `render_digest`, so changing it refreshes cached pages, as does `product_name`. Leave it `nil` to keep the request's host.

Behind a proxy or load balancer, the scheme of the URLs built from the request (when `canonical_url` is `nil`) comes from `X-Forwarded-Proto`: set `config.assume_ssl = true` in production (or have your proxy send the header), or the URLs say `http://`.

## What's new: the unseen count

Shiplog doesn't know your users, so you supply the "last seen" time:

```ruby
# config/initializers/shiplog.rb
config.on_changelog_seen = lambda do |controller|
  user = controller.send(:current_user) # current_user is often private; a Current attribute (Current.user) works too
  # Write only when something is new: the callback runs on every visit, before the page renders.
  user.update_column(:changelog_seen_at, Time.current) if user && Shiplog.unseen_count(since: user.changelog_seen_at).positive?
end
```

```ruby
Shiplog.unseen_count(since: user.changelog_seen_at) # approved features and changes approved after it, at most 99
Shiplog.unseen_count(since: nil)                    # all of them, at most 99
```

```ruby
class ApplicationController < ActionController::Base
  helper Shiplog::UnseenHelper
end
```

```erb
<%= shiplog_unseen_count(current_user.changelog_seen_at) %>
```

The count is one `COUNT` query over the `(status, approved_at)` index. It filters on `approved_at` (when the entry was approved), not on the release date the list is ordered by: "new since you last looked" is about when an entry appeared, so an entry approved today with an earlier `released_on` still counts as new.

`on_changelog_seen` runs **before the page renders**, on the changelog index and on permalink pages whose entry exists, for 200 and 304 answers alike (a visitor whose browser revalidates its cached page has still seen the changelog). Running first means a navbar badge rendered in the same response shows the count after your update. It does not run for 404s (an unknown permalink, a page past the last one), the feed, the roadmap or non-HTML formats. Because it runs on every visit and **may write**, keep it cheap: write only when the stored time is older than the newest entry, as in the example above (one `COUNT`, and a write only when there is something new). The response is not sent yet, so the callback can still set a cookie. An exception in the callback is logged with its class, message and the first five backtrace lines, never shown. A host layout that shows the unseen count renders per-user content, so declare `etag { current_user&.changelog_seen_at }` on your `public_parent_controller`, or a cached page keeps showing the old count.

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
| `switcher` | `shiplog-switcher` | Switcher `nav` (Roadmap, Changelog, extra pages) |
| `switcher_link` | `shiplog-switcher__link` (+ `--current`) | One switcher link |
| `columns` | `shiplog-columns` | Roadmap column grid |
| `column` | `shiplog-column` (+ `--in-progress` / `--coming-soon` / `--later`) | One roadmap column |
| `column_header` | `shiplog-column__header` | Column heading block |
| `column_marker` | `shiplog-column__marker` (+ `--in-progress` / `--coming-soon` / `--later`) | Status dot inside the column `h2`. The column's rule is its `border-top`, set by the column modifier (`shiplog-column--later`); with utility classes, target it with a variant such as `in-[.shiplog-column--later]:bg-gray-300`. |
| `column_title` | `shiplog-column__title` | Column `h2` |
| `column_count` | `shiplog-column__count` | Number of items |
| `column_description` | `shiplog-column__description` | One-line description |
| `column_empty` | `shiplog-column__empty` | Empty column notice |
| `cards` | `shiplog-cards` | List of roadmap cards |
| `card` | `shiplog-card` | Roadmap card |
| `card_title` | `shiplog-card__title` | Card `h3` |
| `card_body` | `shiplog-card__body` | Card text |
| `card_meta` | `shiplog-card__meta` | Line under the card text (omitted when empty) |
| `card_tag` | `shiplog-card__tag` | Repository label |
| `shipped` | `shiplog-shipped` | "Recently shipped" section |
| `shipped_title` | `shiplog-shipped__title` | Its `h2` |
| `shipped_list` | `shiplog-shipped__list` | Its list |
| `shipped_item` | `shiplog-shipped__item` | One entry |
| `shipped_date` | `shiplog-shipped__date` | Release date of the entry |
| `shipped_link` | `shiplog-shipped__link` (+ `--all` on the changelog link) | Links to the changelog |
| `footnote` | `shiplog-footnote` | Footnote paragraph |
| `footnote_link` | `shiplog-footnote__link` (+ `--feed` on the Atom link) | "Suggest a feature" and "Subscribe (Atom)" links |
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
| `search` | `shiplog-search` | Changelog search `form` |
| `search_input` | `shiplog-search__input` | The `type="search"` input |
| `search_button` | `shiplog-search__button` | Submit button |
| `search_summary` | `shiplog-search__summary` | "N results for ..." line |
| `search_clear` | `shiplog-search__clear` | "Clear search" link |
| `search_empty` | `shiplog-search__empty` | "No entries match" notice |
| `permalink` | `shiplog-permalink` (+ `--feature` / `--change`) | The `article` of a permalink page |
| `permalink_back` | `shiplog-permalink__back` | "Back to the changelog" link |
| `permalink_nav` | `shiplog-permalink__nav` | Newer / older `nav` |
| `permalink_nav_link` | `shiplog-permalink__nav-link` (+ `--newer` / `--older`) | One neighbour link |
| `areas` | `shiplog-areas` | The area filter `nav` |
| `area_link` | `shiplog-areas__link` (+ `--current`) | One filter link, "All" included |
| `entry_area` | `shiplog-entry__area` | An entry's area tag |

Values may be strings or arrays. The list is `Shiplog::Classes::KEYS`; assigning `config.classes` raises `ArgumentError` (listing the valid keys) for any other key, in every environment. String keys are accepted and normalised to symbols, and the hash is stored frozen. Texts come from I18n (`shiplog.roadmap.title`, `shiplog.roadmap.lede`, `shiplog.roadmap.*` (`parts`, `shipped_heading`, `full_changelog`, `footnote`, `suggest`), `shiplog.switcher.*`, `shiplog.changelog.*`, `shiplog.categories.feature` / `change`, `shiplog.date_format` (default `%-d %B %Y`, used for entry dates), `shiplog.columns.<column>_description`), so override them in your locale files.

### 4. Override the partials

Copy any view from the engine's `app/views/shiplog/` into your app with the same path and edit it. Each partial documents its locals in a comment on its first lines:

- `shiplog/_page.html.erb`, `shiplog/_page_header.html.erb`, `shiplog/_pagination.html.erb`, `shiplog/_empty.html.erb`
- `shiplog/_switcher.html.erb`
- `shiplog/roadmaps/_column.html.erb`, `shiplog/roadmaps/_card.html.erb`, `shiplog/roadmaps/_shipped.html.erb`
- `shiplog/changelogs/_month.html.erb`, `shiplog/changelogs/_entry.html.erb`, `shiplog/changelogs/_search.html.erb`

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
bin/rails test test/system           # the roadmap board in headless Chrome
bin/rubocop
```

The system tests need Chrome; Selenium fetches a matching chromedriver. The database is configured in `test/dummy/config/database.yml`; set `PGHOST`, `PGUSER` and `PGPASSWORD` if your PostgreSQL needs them.

Tests that call the real GitHub API are skipped by default. To run them:

```sh
SHIPLOG_LIVE_GITHUB=1 GITHUB_TOKEN=... SHIPLOG_LIVE_REPO=owner/name bin/rails test test/live
```

`SHIPLOG_LIVE_REPO` defaults to `Trackberry/shiplog`.

## License

Released under the [MIT License](MIT-LICENSE).

## Releasing

Releases are published by `.github/workflows/release.yml` through RubyGems trusted publishing; there is no API key and no manual `gem push`.

1. Open a pull request that bumps `lib/shiplog/version.rb` and adds a `## x.y.z (date)` entry to `CHANGELOG.md`.
2. Merge it. The workflow reruns the tests, refuses a version that is already on RubyGems, publishes the gem, tags `vx.y.z` and creates the GitHub release with that changelog entry as its notes.

The workflow can also be started by hand (Actions → Release → Run workflow), for the first release or to retry one that failed for an unrelated reason.
