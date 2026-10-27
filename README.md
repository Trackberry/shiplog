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
- Active Storage, only for [screenshots in entries](#screenshots) (the rest works without it)

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
| `prompt_builder` | `nil` | Optional `->(kind:, context:) { String }` replacing the built-in prompts. `kind` is `"roadmap"`, `"feature"` or `"change"`. The built-in prompts ask for the product area; a custom builder must ask for `"area"` in the JSON reply itself (an existing name, or a new one of 1-3 words), and can list the current areas with `Shiplog::Area.ordered.pluck(:name)`. Without `"area"` in the reply, rewrites leave areas alone. |
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
| `changelog_path` | `"changelog"` | Path of the public changelog: segments of letters, digits, `-` and `_`, nested with `/` if you like (`"docs/whats_new"`). Surrounding slashes are stripped (`"/changelog"` is `"changelog"`); a blank value, spaces, dots, `?` or `#` raise `ArgumentError`. Permalinks live below it and the feed is `<path>.atom`. |
| `canonical_url` | `nil` | The site's canonical origin, e.g. `"https://trackberry.com"`. See [Canonical URL](#canonical-url). |
| `extra_pages` | `[]` | Pages added to the switcher after Roadmap and Changelog: `[{ label:, path: }]`, each a String or a callable evaluated in the view. See [Product updates navigation](#product-updates-navigation). Anything else raises `ArgumentError`. |
| `repository_labels` | `{}` | Tag shown on a roadmap card for the repository of its issue: `{ "owner/name" => "iPhone & iPad" }`. Values are Strings or callables evaluated in the view; repositories without one show no tag. |
| `roadmap_shipped_count` | `4` | How many recently shipped changelog entries (features and changes) the roadmap lists below its columns. `0` hides the section. |
| `cache_version` | `nil` | A String added to the public pages' ETag. Callables (`extra_pages`, `repository_labels`, `feedback_path`, `og_image`) cannot be fingerprinted, so bump it when the output of a callable you configured changes. Also bump it when you change your layout's head or override a `shiplog/head/*` partial: ETags don't cover layouts. |
| `feedback_path` | `nil` | Target of the roadmap's "Suggest a feature" link, a String or a callable evaluated in the view. No link while `nil`. |
| `changelog_search` | `true` | Search box on the public changelog and `?q=` filtering. `false` hides the form and ignores `q`. See [Changelog search](#changelog-search). |
| `structured_data` | `true` | schema.org JSON-LD on the public pages (see [Head tags](#head-tags)). `false` emits none. See [Structured data](#structured-data). Part of the ETag. |
| `og_image` | `nil` | The image shared with a permalink page that has no screenshot: `nil` or a callable `->(entry, locale) { url }` evaluated in the view (`instance_exec`, so `main_app` route helpers work). See [Head tags](#head-tags). Anything else raises `ArgumentError`. Only its presence is part of the ETag, not its output: bump `cache_version` when its output changes. |
| `on_changelog_seen` | `nil` | `->(controller) { ... }` called before each changelog index or permalink view renders (also for a 304 revisit), to stamp a visitor's "last seen" time. See [What's new](#whats-new-the-unseen-count). Anything but `nil` or a callable raises `ArgumentError`. |
| `images` | `true` | [Screenshots](#screenshots) in entries. Effective only when Active Storage is loaded in the host; `false` turns fetching, upload and rendering off. `true` or `false`, anything else raises `ArgumentError`. |
| `max_images_per_entry` | `4` | How many images are fetched from the GitHub body of a draft. A non-negative Integer; `0` fetches none (admin uploads are not capped). |
| `locales` | `[]` | Locales entries are translated into when approved, e.g. `[:es]`. An Array of Symbols or Strings (stored as symbols; the default locale `I18n.default_locale` is dropped); anything else raises `ArgumentError`. See [Translations](#translations). Part of the ETag. |
| `announcements` | `:page` | Where [monthly announcements](#monthly-announcements) are published: `:page`, `:external` or `false`. Anything else raises `ArgumentError`. Part of the ETag. |
| `announcement_url` | `nil` | With `announcements = :external`, `->(announcement, locale) { url }` evaluated in the view: where the month heading's summary link goes. |
| `on_announcement_approved` | `nil` | `->(announcement) { ... }`, called once an announcement is approved and translated. See [Monthly announcements](#monthly-announcements). |
| `newsletter` | `false` | Emails the approved announcement to your opted-in users and to the visitors who subscribed. `true` or `false`, anything else raises `ArgumentError`. Needs announcements. Part of the ETag. See [Newsletter](#newsletter). |
| `newsletter_recipients` | `nil` | `-> { User.where(newsletter: true) }`: your users who opted in, each responding to `email`, `locale` and `id` (a relation is read in batches). Never stored. |
| `newsletter_unsubscribe_url` | `nil` | `->(recipient) { url }`: your own settings page, linked as "Preferences" in your users' emails. Must be an absolute http(s) URL; a failure is logged and the footer links Shiplog's page. |
| `on_newsletter_unsubscribe` | `nil` | `->(email) { ... }`, called with the lowercased address on every unsubscribe (one-click, link or preferences page) so your list follows; Shiplog suppresses the address itself either way. Errors are logged. Warned about at boot when missing with `newsletter_recipients`. |
| `newsletter_from` | `nil` | The sender, e.g. `"Acme <updates@acme.com>"`; also used by the confirmation email. Falls back to `ActionMailer::Base.default[:from]`. Required to send. |
| `newsletter_address` | `nil` | The postal address in the footer, required to send (CAN-SPAM). |
| `newsletter_logo_url` | `nil` | The logo in the email, an absolute http(s) URL shown 140px wide. Anything else raises `ArgumentError`. |
| `newsletter_accent` | `nil` | The colour of buttons and links in the email, `"#rrggbb"` (default `#0969da`). Anything else raises `ArgumentError`. |
| `newsletter_mailer_options` | `{}` | A Hash merged into every newsletter message's `mail(...)`: `{ message_stream: "broadcast" }` for a Postmark broadcast stream, `delivery_method_options`, ... Keys that would change the recipients, the sender or the content (`to`, `cc`, `bcc`, `from`, `reply_to`, `subject`, `body`, `template_name`, ...) raise `ArgumentError`. Not applied to the confirmation email. |
| `newsletter_batch_size` | `500` | How many recipients a send reads at a time (1 to 10,000); rows are claimed and emailed 100 at a time within. |
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

Webhooks can be missed, so schedule these jobs:

- `Shiplog::SyncJob`: reconciles issues and pull requests and creates missing drafts. Every 30 minutes is a good start. The first run backfills everything.
- `Shiplog::ScanChangesJob`: looks at default-branch commits without a pull request, then drafts small changes. Run it weekly.
- `Shiplog::DraftAnnouncementJob`: drafts the previous month's [announcement](#monthly-announcements). Run it early each month, after the month's last weekly scan if you can.
- `Shiplog::PurgeNewsletterJob` (with `config.newsletter`): deletes the [newsletter](#newsletter) subscribers who never confirmed within 30 days and the delivery rows older than 180 days. Run it weekly.

GoodJob (`config/initializers/good_job.rb` or `config/application.rb`):

```ruby
config.good_job.enable_cron = true
config.good_job.cron = {
  shiplog_sync: { cron: "*/30 * * * *", class: "Shiplog::SyncJob" },
  shiplog_scan_changes: { cron: "0 6 * * 1", class: "Shiplog::ScanChangesJob" },
  shiplog_announcement: { cron: "0 7 2 * *", class: "Shiplog::DraftAnnouncementJob" },
  shiplog_purge_newsletter: { cron: "0 5 * * 1", class: "Shiplog::PurgeNewsletterJob" }
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
  shiplog_announcement:
    class: Shiplog::DraftAnnouncementJob
    schedule: at 7am on the 2nd day of every month
  shiplog_purge_newsletter:
    class: Shiplog::PurgeNewsletterJob
    schedule: every monday at 5am
```

You can also trigger a sync from the admin Sync page. Rewriting always runs in `Shiplog::RewriteEntryJob`, never in a request.

## The rewriter

`config.rewriter` is a callable that receives the prompt (a String) and returns a String containing a JSON object:

```json
{"title": "...", "body": "...", "customer_facing": true, "area": "Billing"}
```

`area` is optional (see [Product areas](#product-areas)); a reply without it works as before.

Shiplog extracts the first valid JSON object from the reply, so models that wrap it in prose or code fences still work. `customer_facing: false` means the model thinks the change is irrelevant for customers; such small changes are stored as discarded and can be restored by an admin. If no rewriter is configured, the reply can't be parsed or the call raises, the entry keeps the original GitHub text and the error is shown in the admin, where you can edit the text or regenerate.

The same callable also receives the translation, area-name translation and area-detection prompts, whose replies are other JSON shapes (`{"title", "body"}` for a translation, `{"areas": [...]}` or `{"assignments": [...]}` for areas). It must handle free-form prompts: pass the prompt to your model as is, and return its text reply, without assuming the rewrite schema above.

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

**Keeping search pages out of search engines.** A page with a query is `noindex`: `shiplog_head_tags` renders `<meta name="robots" content="noindex">` (see [Head tags](#head-tags)). Hosts still on the older blocks read `content_for :shiplog_robots`.

## Product areas

The rewriter groups entries into product areas ("Billing", "Reports"), and the changelog lets visitors filter by area.

- **Detection while rewriting.** The prompt lists the existing areas (as data, before the `<source>` block) and asks the model for `"area"` in its JSON reply: an existing name, or a new name of 1-3 words when none fits. Shiplog matches the name against the existing areas ignoring case, then by slug, and creates a new area only while fewer than `config.max_areas` (default 8) exist and the name is valid: at most 40 characters, letters, digits, spaces, `&` and `-`. Any other name leaves the entry's current area as it is (a rewrite never erases an area). A reply without `"area"` (or with one that is not a String) changes nothing. Roadmap entries get areas too, but only features and changes show them publicly. A custom `config.prompt_builder` builds its own prompt, so it has to ask for `"area"` itself and can read the existing areas with `Shiplog::Area.ordered.pluck(:name)`.
- **Detect areas.** The admin has an Areas page with a "Detect areas" button, which enqueues `Shiplog::DetectAreasJob`. With no areas yet, the job asks your `config.rewriter` (same callable, a dedicated prompt, reply `{"areas": [...]}`) to propose up to `max_areas` areas from the titles of up to 200 approved features and changes. Then it classifies the draft and approved entries that have no area, 50 titles per prompt (reply `{"assignments": [{"id": 1, "area": "Billing"}]}`), using only existing areas; unknown ids and areas are ignored. It is idempotent (it only touches entries without an area), bounded (at most 20 classification prompts, 1000 entries, per run; click again for more) and logs what it did (`[shiplog] Detect areas: ...`). Each entry it sent is stamped (`area_detected_at`), placed or not, so entries the AI declined are not asked again and the next run moves on to the rest; tick "Re-check unplaced entries" next to the button (for example after renaming, merging or adding areas) to ask about them again. Only one detection runs at a time (a database advisory lock); a second one logs and returns. The button needs `config.rewriter` (without it nothing is enqueued and a flash says so). The job never retries: a failure is logged (class, message, first 5 backtrace lines) and the Areas page shows "Last detection: <time>, assigned N" or the error from the last run (stored in the `shiplog_settings` table). After clicking, refresh to see the result. The titles are sent, never the bodies.
- **Admin.** The Areas page lists areas with their entry counts. You can rename (the slug follows, translated names are dropped and translated again), move up/down, merge into another area (moves the entries, deletes the source) and delete (the entries have no area). The entry edit page has an Area select with "None"; changing it marks the entry as set by an admin (`area_set_by_admin`), and neither rewrites nor detection ever change such an entry's area. The inbox shows the area as a badge.
- **Public.** With at least 2 areas that have published features or changes, the changelog shows an "All" link and one link per area above the list (`?area=slug`, the `areas` / `area_link` keys, `--current` on the selected one). It combines with search and pagination (the links keep both) and is part of the ETag, with the names, slugs and order of all areas. An unknown `?area=` slug answers 404; a blank one is ignored. Every entry shows its area as a tag (`entry_area`), in the list and on the permalink page. The Atom feed adds `<category term="slug" label="Name"/>` to entries with an area and honours `?area=` (404 for an unknown one). Roadmap cards don't change.
- **Translated names.** With `config.locales` set, area names are translated too; see [Translations](#translations). Public pages show `area.display_name`.
- **Texts:** `shiplog.changelog.areas.label` and `.all`, and `shiplog.admin.areas.*`, `shiplog.admin.nav.areas`, `shiplog.admin.entries.no_area` and `.fields.area`; all have English defaults.
- **Schema:** the `shiplog_areas` table (`name`, `slug` unique, `position`) and `shiplog_entries.area_id` (nullable foreign key, `ON DELETE SET NULL`) and `area_set_by_admin`. The cap is checked under a Postgres advisory lock, so two rewrites racing for the last slot cannot go past it. Also `shiplog_entries.area_detected_at` (entries already sent to detection) and `shiplog_settings` (the last detection run).

## Translations

Set `config.locales = [:es]` and entries are translated into Spanish by your `config.rewriter`, then published with the English text: **there is no second approval**.

- **When.** `Shiplog::TranslateEntryJob` is enqueued for each configured locale when an entry is approved (roadmap entries too), and when the English title or body of an approved entry changes (an admin edit). Editing anything else (the release date, the area) does not translate. Drafts, discarded entries and the unpublishing "Regenerate" (which returns an entry to draft) do not either.
- **How.** One LLM call per entry, per locale and per change. The prompt asks for the title and body in the language of the locale (Shiplog names about 40 languages; any other locale code is named by its code), keeping the meaning, the tone, product names, numbers, links and formatting, with your `tone`, `audience` and `product_name` as context, and for a JSON reply `{"title": "...", "body": "..."}`. The English text goes inside `<source>` and is neutralised like the rewriting prompts (a `<source>` or `</source>` in it becomes `[source]`). The reply is validated like the English kinds: strings, a non-blank title, at most 120 characters of title and 2000 of body (a roadmap body is cut at the roadmap limit, about 220 characters, so a translation longer than that loses its last sentence). A custom `config.prompt_builder` is for rewriting GitHub text and is not used here.
- **Stored in** `shiplog_entry_translations` (`entry_id`, `locale`, `title`, `body`, `source_digest`, `edited_by_admin`; unique on `[entry_id, locale]`, deleted with the entry). `source_digest` is the SHA-256 of the English title and body the translation was made from.
- **The stale rule.** A translation is current while its `source_digest` matches the entry's English text now. Pages show it only then; a missing or stale one shows the English text. A job whose translation is current does nothing and makes no LLM call, so repeated approvals and double clicks cost nothing. The job checks again, under the entry's row lock, before it writes: if the entry was unpublished or its English text changed meanwhile, the result is dropped (the change enqueued its own job).
- **Admin edits.** The entry edit page has a Translations section per locale with the title and body, editable. Saving marks the translation as edited by an admin and as made from the current English text (so it shows at once, even when it was stale). An edited translation is kept as long as the English text stays the same; when the English text changes, the new translation replaces it and clears the mark (the replacement is logged). The section marks each locale as Missing, Stale, Up to date, and Edited by an admin. **Retranslate** enqueues the job with `force: true`, which ignores the digest and an admin's edit.
- **Entries approved before 0.3.0** (or before you set `config.locales`) have no translations: run `bin/rails shiplog:translate_approved`. It enqueues `TranslateEntryJob` for every approved entry and configured locale that has no current translation, reading entries in batches (`BATCH_SIZE=100` by default), and prints the counts per locale (and enqueues `TranslateAreaJob` for areas missing a name in some locale). It is idempotent: what is current is not enqueued, and the job's digest check skips it anyway. It needs `config.locales` and `config.rewriter`, and costs one LLM call per job.
- **Errors.** A failing rewriter (or an unusable reply) is logged and retried twice with a growing wait (`retry_on StandardError, attempts: 3, wait: :polynomially_longer`), then logged and dropped: the English text stays shown and Retranslate tries again. Without `config.rewriter` nothing is translated. An entry deleted since the job was queued is ignored.
- **Area names.** `areas.name_translations` (jsonb, keyed by locale string) holds each area's name per configured locale, and `Area#display_name(locale = I18n.locale)` returns the translation for a locale in `config.locales`, else the name. The filter pills, the entry tags, the permalink tag and the Atom `<category label>` use it; slugs and the category `term` stay English, so `?area=` URLs are the same in every locale. `Shiplog::TranslateAreaJob(area, force: false)` is enqueued when an area is created (a rewrite, detection) or renamed, if `config.locales` and `config.rewriter` are set. It makes one call for all locales (the name inside `<source>`, neutralised; reply `{"es": "..."}`); every locale asked for must come back as a valid area name (at most 40 characters, letters, digits, spaces, `&`, `-`) or the reply is rejected, retried twice and dropped like entry translations. Without `force` it only fills locales that have no name and never touches an existing one, so a repeat costs no call. A rename drops the stored translations and translates the new name. The Areas page shows a field per locale on each area: what an admin types is kept (an empty field removes it) until the area is renamed or forced. **Translate names** enqueues the job for the areas missing a name in some locale; it only fills in the missing names, so edits are kept. `bin/rails shiplog:translate_approved` enqueues the job (no force) for those areas too. The ETags include the translated names.
- **Unpublishing.** The job writes nothing for an entry that is not approved. Discarding keeps the rows, but they are never shown: every public query lists approved entries only.
- **Public pages.** When `I18n.locale` is one of `config.locales`, the roadmap cards, the changelog list, the permalink page (title, body, `<title>`, meta description and Open Graph tags), the Atom feed and the "Recently shipped" list show `entry.display_title` and `entry.display_body` (the translation, else English); call them in your own views. Translations are loaded for the current locale only, in one query per page. Slugs stay English and are shared by all locales. Under the default locale or any other, nothing is queried and English shows. Screenshots' default alt text follows the title shown.
- **Search** under a translated locale matches the translated title or body of a current translation, or the English text, with the same escaping.
- **Feed.** `/changelog.atom` follows the request locale (`xml:lang`); an entry's `updated` is the later of its own and its translation's.
- **Caching.** The ETag includes the locale, `config.locales` (through `render_digest`) and the id and `updated_at` of the translations shown.
- **Routing is yours.** Shiplog renders under whatever `I18n.locale` your app sets; it adds no locale routes. For `/es/roadmap` and `/es/changelog`, scope your engine mount or set the locale in a controller concern or middleware (the test app uses a tiny middleware that moves `/es` into `SCRIPT_NAME`, so links keep the prefix). A host that redirects `/es/...` to English has to stop doing so. The locale must be in `I18n.available_locales`.
- **The gem's own texts.** `config/locales/es.yml` translates every `shiplog.*` key (public and admin) into neutral Spanish, and the month names its date formats use. Override any key in your own locale files; `test/shiplog/es_locale_test.rb` keeps `es.yml` complete, and you can copy it for another language.
- **Cost.** Each approval and each English edit of an approved entry costs one LLM call per locale; a Retranslate costs one.

## Screenshots

Entries can show screenshots: the first one on the changelog list, all of them on the entry's permalink page, and in the Atom feed and the `og:image` tag.

- **Needs Active Storage.** The host must load it (`require "active_storage/engine"` in `config/application.rb`, or `rails/all`) and have its tables (`bin/rails active_storage:install`, then `db:migrate`). Without it, or when its tables (`active_storage_attachments`, `active_storage_blobs`) don't exist yet, screenshots are off: nothing is fetched, uploaded, queried or rendered, nothing crashes, and Shiplog logs the reason once (`[shiplog] Screenshots are off: Active Storage is not loaded...` at boot, or `...tables are missing...` the first time a page checks; the check runs once per process and is not repeated per request). `config.images = false` turns them off too. Shiplog declares `has_many_attached :images` on `Shiplog::Entry` only when Active Storage is loaded. Active Storage's routes belong to your app: Shiplog's views reach them through `main_app`.
- **From GitHub.** When a draft is written (and when it is regenerated), the job fetches the issue's or pull request's rendered body (`bodyHTML`, one small GraphQL query per draft, so the sync payloads don't grow) and downloads the `<img>` images in it, at most `config.max_images_per_entry` (4). It only does so for a draft that has no images yet: images of an approved entry are never changed automatically, and nothing is fetched twice. Only these hosts are fetched, https only, exact host match: `private-user-images.githubusercontent.com`, `user-images.githubusercontent.com`, `camo.githubusercontent.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com` and `github.com` for `/user-attachments/assets/` paths. `github.com` paths must be exactly `/user-attachments/assets/<letters, digits and dashes>` (an encoded `..` or `%2f` is refused). `raw.` and `objects.githubusercontent.com` are on the list because GitHub serves attachments, and redirects them, from there. Redirects are followed up to 3 times, each checked against the list again, and the body of a redirect is read under the same size cap. Timeouts are 5 seconds (connect and read), a download gets 15 seconds in total (checked while streaming and between redirects, on a monotonic clock) and all the images of one entry 45 seconds (the rest are skipped and logged), the size limit is 5 MB of raw bytes (requests send `Accept-Encoding: identity`; the download stops past the limit), and the type is decided by the file's first bytes: PNG, JPEG, GIF or WebP only (SVG and HTML are refused, whatever the extension says). The pixel size is read from the header too (no decoding): an image over 10,000 pixels on a side or 40 megapixels, or one whose size can't be read, is refused, for downloads and for admin uploads alike. The width and height are stored in the blob's metadata at once, so the pages carry them without waiting for Active Storage's analysis. The GitHub token is sent to `github.com` only, never to the other hosts; signed `private-user-images` URLs need none. Any failure is logged and skipped, and never fails the draft. The token needs no extra permission.
- **Admin.** The entry edit page lists the images in order, each with an alt text field, "Remove" and "Up"/"Down" buttons, plus an upload form (several files; same type and size checks, done on the file's bytes on the server). Thumbnails are 200px variants when the `image_processing` gem is in your bundle and a processor is available (`ruby-vips` loads, or `mini_magick` is in the bundle), else the original, sized by CSS.
- **Order and alt text.** Stored on the entry: `image_order` (jsonb, blob ids in order) and `image_alts` (jsonb, blob id => text). An image without alt text uses the entry's title. `Shiplog::Entry#ordered_images` returns the attachments in order.
- **Public.** `<img loading="lazy">` with the alt text, `width` and `height` (taken from the image's header when it is attached, so they don't wait for the analysis). The URLs come from your routes (`url_for` on the attachment, so `resolve_model_to_route` applies). The `og:image` and the feed use the absolute URL (`config.canonical_url` when set). The ETags include the images' blob ids, order, alt texts and sizes.
- **Texts:** `shiplog.admin.entries.images.*`, all with English defaults.
- **Schema:** `shiplog_entries.image_order` and `.image_alts`, in the 0.3.0 migration, plus Active Storage's own tables.

## Entry permalinks

Every approved feature and change has its own page at `GET /changelog/:slug` (under `config.changelog_path`). The changelog list links each title to it. Roadmap entries have no permalink.

- **Slug:** made when the entry is first approved, from the title (`parameterize` with underscores turned into dashes, so `a-z`, `0-9` and single dashes only; at most 80 characters, `entry-<id>` when nothing is left) and made unique with `-2`, `-3`, ... A later title edit keeps the slug, so links never break; restoring and re-approving an entry keeps it too. A unique index (partial, on non-null slugs) guards against two approvals racing for one slug, and the loser retries.
- **Entries approved before 0.3.0** get their slug from the 0.3.0 migration (oldest first, so the oldest keeps the plain slug on duplicate titles). `bin/rails shiplog:backfill_slugs` (idempotent, oldest first) does the same for entries that old code approved during a deploy window. The public pages never write, because a host may send GETs to a read replica: an approved entry without a slug is listed without a link, left out of the feed and has no page until it has a slug. An entry whose stored slug the route rejects is treated the same way.
- **The page** shows the entry, a "← Back to the changelog" link to the entry's month anchor, and its newer and older neighbours (`rel="prev"` and `rel="next"`, as in the pagination). Drafts, discarded and roadmap entries and unknown slugs answer 404 with `X-Cascade: pass`: the engine is usually mounted at `/`, and its `/changelog/:slug` route would otherwise shadow a host route of yours below the changelog path (say `/changelog/archive`, declared after the mount). The router carries on with the routes after the mount, and your own 404 shows if none matches. Declare such host routes after `mount Shiplog::Engine`; before it they win anyway.
- **Caching:** the ETag covers the entry and its neighbours' ids and `updated_at`.
- **Head tags:** the page's description (the body, cut at 160 characters), canonical link and Open Graph tags (`og:title`, `og:description`, `og:type` = `article`, `og:url`, and the image) come from `shiplog_head_tags`; see [Head tags](#head-tags).
- **Styling:** the `permalink` (the `article`), `permalink_back`, `permalink_nav` and `permalink_nav_link` keys of [`config.classes`](#3-configclasses-tailwind-and-other-utility-frameworks). Override `shiplog/changelogs/_entry_content.html.erb` (locals `entry:`, `heading:`, `linked:`) to change what an entry shows in both the list and the permalink page.
- **Texts:** `shiplog.permalink.title`, `.back`, `.nav_label`, `.newer` and `.older` (with `title`); all have English defaults.

## Structured data

The public pages describe themselves to search engines with schema.org JSON-LD: one `<script type="application/ld+json">` per page, rendered by `shiplog_head_tags` (see [Head tags](#head-tags); leave it out with `except: :structured_data`). The older `content_for :shiplog_structured_data` block still holds the same tag.

- **Permalink page:** an `Article` with `headline` (the title, at most 110 characters), `description` (the meta description), `inLanguage` (`I18n.locale`, e.g. `en`, `es`), `datePublished` (the release date), `dateModified`, `url` and `mainEntityOfPage` (the permalink, honouring `config.canonical_url`), `image` (absolute URLs of the screenshots, else the `config.og_image` image, left out without any), `articleSection` (the area's name, when it has one), `publisher` (an `Organization` named `config.product_name`, left out while it is `nil`) and `isPartOf` (the changelog's `CollectionPage`). Titles and bodies follow the request locale, translations included.
- **Changelog list:** a `CollectionPage` whose `mainEntity` is an `ItemList` of the entries on the current page (`position` counted on the page, `url`, `name`). Entries without a valid slug are skipped. Search results (they are `noindex`) and an empty list have none.
- **Roadmap:** a `CollectionPage` with an `ItemList` of the cards (`position` and `name`; roadmap cards have no permalink, so no `url`).
- **Safety:** the JSON is built from a Ruby Hash and `<`, `>` and `&` are written as `\u003c`, `\u003e` and `\u0026`, so a title containing `</script>` cannot close the tag.
- **Off:** `config.structured_data = false` emits none. It is part of the ETag.

## Head tags

Shiplog's pages describe themselves in the `<head>`: description, canonical link, robots, Open Graph, Twitter card, the Atom feed link and JSON-LD. Shiplog's own layout renders them. If you set `config.public_layout` to a layout of your own, add one line to its `<head>`:

```erb
<head>
  <title><%= content_for(:title) %></title>
  <%= shiplog_head_tags %>
</head>
```

`shiplog_head_tags` is available in every view of your app (the only Shiplog helper that is), and on any page that is not a Shiplog page it returns an empty string, so it is safe in a layout shared with your own pages. Call it in the layout, not inside a component (ViewComponent, Phlex): in a view that doesn't have Shiplog's helpers it also returns an empty string. `<title>` stays yours: it is `content_for(:title)`.

After changing your layout's `<head>` or overriding a `shiplog/head/*` partial, bump `config.cache_version`: ETags don't cover layouts, so visitors with a cached page would keep the old tags.

- **What each page gets.** Permalink: `description`, `canonical` (the permalink), `og:title`, `og:description`, `og:type` = `article`, `og:url`, `og:image` and `og:image:alt` when there is an image, `twitter:card` (`summary_large_image` with an image, `summary` without) and `twitter:image`, the Atom link and the `Article` JSON-LD. Changelog list: `canonical` (the list's own URL, with its `area` and `page` but without any other query parameter), `og:title`, `og:type` = `website`, `og:url`, `twitter:card` = `summary`, the Atom link and the `CollectionPage`. Roadmap: the same without the Atom link. Each key is emitted once.
- **Search pages** (`?q=`) are `noindex` and have **no canonical** (and no `og:url`, no JSON-LD). The alternative, a canonical pointing at the plain list, would tell search engines to index a page while `noindex` tells them not to; mixed signals are ignored or worse, so a search page just asks not to be indexed.
- **`except:`** leaves groups out, for tags your layout already writes: `shiplog_head_tags(except: [:canonical, :twitter])`. Valid keys: `:description`, `:canonical`, `:robots`, `:open_graph` (the `og:*` tags), `:twitter` (the `twitter:*` tags), `:feed` and `:structured_data`. Any other key raises `ArgumentError`.
- **`except: :canonical` and `og:url`.** `except: :canonical` drops only the `<link rel="canonical">`. `og:url` keeps Shiplog's canonical, which honours `config.canonical_url`; to change it, drop `:open_graph` too. A host that writes its own canonical should make it agree with that one, and should not emit a canonical on search pages, where Shiplog sets `noindex`: Shiplog fills `content_for(:shiplog_robots)` with `"noindex"` there (and leaves it empty elsewhere), which your layout can check.
- **Overridable partials.** Copy one into your app at the same path to change it (like the other [partials](#4-override-the-partials)):

  | Partial | Renders |
  |---|---|
  | `shiplog/_head_tags.html.erb` | renders the four below |
  | `shiplog/head/_meta.html.erb` | `description`, canonical link and `robots` |
  | `shiplog/head/_open_graph.html.erb` | `og:*` and `twitter:*` |
  | `shiplog/head/_feed.html.erb` | the Atom `<link rel="alternate">` |
  | `shiplog/head/_structured_data.html.erb` | the JSON-LD `<script>` |

  Every partial gets the same locals: `head` (a Hash with `:kind` (`:permalink`, `:changelog` or `:roadmap`), `:title`, `:entry` (permalink only), `:image`, `:canonical` and `:description`), `description`, `canonical`, `robots`, `open_graph` and `twitter` (Hashes of tag name to content), `feed_url`, `feed_title` and `json_ld`. What `except:` removed arrives as `nil` or `{}`, so a partial that renders its locals respects it.
- **The share image.** The permalink page's image is the first screenshot whose URL can be built (absolute URL), else what `config.og_image` returns, else none. `config.og_image` is `nil` or `->(entry, locale) { url }`, evaluated in the view (`instance_exec`, so `main_app.my_card_url(entry.slug)` works). A path (`"/cards/dark.png"`) is made absolute with `config.canonical_url` or the request's origin. A callable that raises, or returns anything but an http(s) URL or a path (`javascript:`, `//host`, `nil`), is logged once for the page (`[shiplog] config.og_image ...`) and the page renders without the image. `Article.image` of the JSON-LD lists all the screenshots with a URL, else that same callable image. List pages and the roadmap get no image from Shiplog: your default applies, through your own tags (`except: [:open_graph, :twitter]`) or an override of `_open_graph`.
- **The older `content_for` blocks** (`:shiplog_description`, `:shiplog_og`, `:shiplog_feed`, `:shiplog_robots`, `:shiplog_structured_data`) are still filled as in 0.3.0 and still work, but are superseded. The one difference: `:shiplog_og` now includes the `config.og_image` fallback image when that is set and the entry has no screenshot. Use `shiplog_head_tags` **or** the blocks, not both: `shiplog_head_tags` never reads the blocks, so a layout that renders both emits the tags twice. The blocks have neither the canonical link nor the Twitter tags. Upgrading: replace the `content_for` renders in your `<head>` with `shiplog_head_tags`, and pass `except:` for the tags your layout writes itself.

## Atom feed

`GET /changelog.atom` serves the latest 50 approved features and changes (newest first) as an Atom feed. An entry has a stable id (a tag URI built from the permalink path, so a title edit does not change it), its permalink, `published` (the release date), `updated`, and its body as HTML. All URLs are absolute. The feed is cached with an ETag like the pages and answers 304 on a match; it does not call `on_changelog_seen`.

The changelog and permalink pages advertise it with a `<link rel="alternate" type="application/atom+xml">` (rendered by `shiplog_head_tags`, see [Head tags](#head-tags); the older `content_for :shiplog_feed` block holds the same link) and the changelog shows a visible "Subscribe (Atom)" link (the `footnote_link` key). The feed has an `<author>` (the product name, or "Changelog"), which RFC 4287 requires when entries carry none. The feed is titled "Changelog", or "<product_name> changelog" when `config.product_name` is set, and follows the request locale. Texts: `shiplog.feed.title_with_product`, `.link_title` and `.subscribe`.

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

## Monthly announcements

Once a month, Shiplog drafts a short **announcement** of what shipped: an intro, two or three highlights linking to their permalink pages, and an "Also improved" list grouped by product area. Your `config.rewriter` writes it, in Markdown, from the month's approved features and changes and from the small changes that got no entry of their own (changes the AI judged not customer-facing, and merged pull requests without an entry). An admin edits and approves it like any other entry. Nothing is public before that.

The changelog stays the daily stream. The announcement is its monthly summary.

**Drafting.** Schedule `Shiplog::DraftAnnouncementJob` early each month (see [Scheduling](#scheduling)). It drafts the previous month, once: running it again does nothing. A month without an approved feature or change gets no draft. The inbox also has "Draft announcement for <month>" buttons for the current and the previous month, and `bin/rails shiplog:draft_announcement MONTH=2026-10` drafts any month. Without a rewriter, the draft is a skeleton listing the month's entries with links, ready to edit, and Regenerate rebuilds it from the month's current entries. A month drafted from the button before it ended is not drafted again by the job: regenerate it once the month is over.

An announcement belongs to a month, so its page is `/changelog/2026-10`. The `YYYY-MM` slug is set when it is drafted, and features and changes never get a slug of that shape. If a month's entries change after the draft was written, the inbox flags "The month's entries changed since this draft": regenerate it, or edit it. Regenerating an approved announcement returns it to draft, as for other entries.

**Where it is published** is `config.announcements`:

| Value | What happens |
|---|---|
| `:page` (default) | Shiplog renders `/changelog/2026-10`, links it from the month's heading on the changelog ("Read the October 2026 summary") and adds it to the Atom feed. |
| `:external` | No Shiplog page. The month's heading links to `config.announcement_url`, and your app publishes the text itself through the hook below. |
| `false` | No announcements: nothing is drafted, rendered or announced. |

```ruby
config.announcements = :external
config.announcement_url = ->(announcement, locale) { main_app.blog_post_path(announcement.slug, locale:) }
```

`announcement_url` is evaluated in the view, so route helpers work. A nil or unsafe result renders no link. Bump `config.cache_version` when its output changes.

**The approval hook.** `config.on_announcement_approved` is called with the announcement once it is approved **and** translated into every configured locale (right after approval with no `config.locales`, or with no rewriter to translate). It runs once per approval, in `Shiplog::AnnounceJob`: an announcement regenerated and approved again is announced again. The hook runs inside the announcement's row lock and is only marked done when it returns, so a hook that raises, or a worker that dies during it, is called again by the retry (twice at most). Keep it fast and idempotent: enqueue your own job, as below. The same moment sends an `announcement_approved.shiplog` ActiveSupport notification with `announcement:` in the payload. If the hook gave up, or a translation never arrived, the admin page has a "Notify now" button, which does not wait for translations (missing ones fall back to English). Editing an approved announcement's text does not call the hook again.

```ruby
config.on_announcement_approved = ->(announcement) { BlogImportJob.perform_later(announcement.id) }
```

The announcement is a `Shiplog::Entry` that offers what you need to publish it elsewhere, in the default locale or any configured one:

```ruby
announcement.display_title(:es) # the Spanish title, or English without a current translation
announcement.to_markdown(:es)   # the body as written (Markdown)
announcement.to_html(:es)       # rendered and escaped, safe to embed
announcement.to_text(:es)       # plain text, e.g. for an email's text part
announcement.public_url         # its Shiplog page (absolute with config.canonical_url)
announcement.slug               # "2026-10"
```

**Export.** The announcement's admin page has a preview, and Markdown, HTML and plain-text downloads in each locale, for blogs and newsletter tools without an API.

**Badge.** `Shiplog.unseen_announcements_count(since:)` (and `shiplog_unseen_announcements_count(since)` in views) counts approved announcements, where `Shiplog.unseen_count` counts every feature and change. Badge the rare monthly summary rather than every daily entry. `config.on_changelog_seen` also runs on an announcement's page, and `controller.shiplog_entry` is the entry being viewed, so you can stamp a separate "announcements seen" time:

```ruby
config.on_changelog_seen = lambda do |controller|
  user = controller.send(:current_user)
  next unless user

  if controller.shiplog_entry&.announcement?
    user.update_column(:announcements_seen_at, Time.current) if Shiplog.unseen_announcements_count(since: user.announcements_seen_at).positive?
  elsif Shiplog.unseen_count(since: user.changelog_seen_at).positive?
    user.update_column(:changelog_seen_at, Time.current)
  end
end
```

**Translations** follow the entries' flow: an approved announcement is translated into `config.locales`, keeping its Markdown and links.

**Styling.** The page uses `shiplog-announcement`, `shiplog-announcement__title` and `shiplog-announcement__body`; the month link uses `shiplog-month__announcement` and `shiplog-month__announcement-link`. All are `config.classes` keys. The body's HTML comes from a small built-in Markdown renderer (headings, paragraphs, lists, links, images, emphasis, code, quotes) that escapes everything else.

**Prompt.** `config.prompt_builder` receives `kind: "announcement"` and a context Hash: `month`, `entries` (each with `kind`, `title`, `body`, `area`, `url`) and `skipped` (titles). Ask for `{"title": "...", "body": "..."}` with a Markdown body, or return `nil` for this kind to keep the built-in prompt.

**Links** in the draft are the entries' permalink URLs, absolute when `config.canonical_url` is set (set it: the text travels to the feed, exports and your hook). With the engine mounted under an optional segment (`scope "(:locale)"`), they are the default locale's URLs.

## Newsletter

Optional, off by default. The approved announcement goes out by email, in each recipient's language, to your users who opted in and to the visitors who subscribed through Shiplog's form. Approving publishes the announcement; sending the newsletter is a separate, explicit action on the announcement's admin page.

**Setup.**

```ruby
Shiplog.configure do |config|
  config.newsletter         = true
  config.newsletter_from    = "Acme <updates@acme.com>"
  config.newsletter_address = "Acme Inc., 123 Main Street, Springfield"   # the footer's postal address (CAN-SPAM)
  config.canonical_url      = "https://acme.com"                          # the links in emails are absolute
  config.newsletter_logo_url = "https://acme.com/logo.png"                 # optional branding
  config.newsletter_accent   = "#0969da"
end
```

Then run the migrations (`bin/rails shiplog:install:migrations && bin/rails db:migrate`): the newsletter adds `shiplog_newsletter_subscribers` and `shiplog_newsletter_deliveries`. The admin nav gets a Newsletter page, and the changelog and announcement pages get a subscribe form. At boot, Shiplog logs what is still missing to send.

**Recipients: your users.** Shiplog never stores them. Give it a callable returning objects that respond to `email`, `locale` and `id` (an Active Record relation is read in batches), and two hooks so an unsubscribe reaches your side too:

```ruby
config.newsletter_recipients      = -> { User.where(newsletter: true) }
config.newsletter_unsubscribe_url = ->(user) { Rails.application.routes.url_helpers.settings_url(host: "acme.com") }   # optional
config.on_newsletter_unsubscribe  = ->(email) { User.where("lower(email) = ?", email).update_all(newsletter: false) }
```

You own the opt-in, the settings toggle and the locale: resolve it yourself (for Trackberry: the user's locale, then the organization's default, then English). A locale that is not the default nor one of `config.locales` gets the default language. Objects without a usable email or id are skipped with a warning (which names no address).

How an unsubscribe works for your users: every newsletter carries the RFC 8058 one-click headers (`List-Unsubscribe` and `List-Unsubscribe-Post`, which Gmail and Yahoo require from bulk senders) pointing at Shiplog's own endpoint, `POST /shiplog/newsletter/unsubscribe/<token>`, where the token is the recipient's email, encrypted and signed with a key derived from your app's `secret_key_base` (nothing in a link or a log reveals the address). So Shiplog needs no row for your users until they unsubscribe, and one endpoint serves both lists: it records the unsubscribe in Shiplog, as a *suppression row* in `shiplog_newsletter_subscribers` holding that one email (created when the address has no row, marked when it has), and calls `on_newsletter_unsubscribe` with the lowercased email so your own setting follows. From then on the address is skipped at send time even if your list still returns it: an unsubscribe is honoured whether or not your hook works. Set the hook anyway (Shiplog warns at boot when `newsletter_recipients` is set without it), or your settings page will show the user as subscribed. When a user opts in again in your app, lift the suppression:

```ruby
Shiplog::Newsletter.resubscribe(user.email)   # true when the address was suppressed
```

A suppression-only row is deleted (nothing is left to store); a visitor who had confirmed through Shiplog's form is confirmed again. The footer's "Unsubscribe" link opens the same endpoint as a page with a button (a GET changes nothing: mail scanners prefetch links). The footer's "Preferences" link is `newsletter_unsubscribe_url` when you set it (your own settings page, evaluated with the recipient object), else Shiplog's unsubscribe page. These pages keep working after you turn `config.newsletter` off (or announcements): a link in an old email must still unsubscribe. If you rotate `secret_key_base`, call `Shiplog::Newsletter::Tokens.rotate(old_secret_key_base)` in an initializer while old links must keep working.

**Recipients: visitors.** The subscribe form is on the changelog and on each announcement page, and you can render it on any page:

```erb
<%# a host view; add `helper Shiplog::NewsletterHelper` to the controller %>
<%= shiplog_newsletter_form %>
```

One email field, a hidden honeypot, a plain POST that works without JavaScript. Double opt-in: the form creates a pending subscriber with the page's locale (if it is the default or one of `config.locales`) and the page it was on (`source`, a consent record: a same-site path, anything else is dropped), and emails a confirmation link valid 7 days; the link opens a page with a button, and the button confirms. The link is single use (an encrypted nonce, spent when it confirms, voided by an unsubscribe, replaced when a new confirmation is sent), so a replayed link resubscribes nobody. Only confirmed subscribers receive the newsletter. The form answers the same thing for a new, pending, confirmed or unsubscribed address, so it reveals nothing; a confirmed address gets no new email, and an existing row keeps its locale and source (an anonymous submission cannot rewrite them). Attempts are rate limited per address (3 an hour, keyed by a digest of the address without `+tag` and, for Gmail, without dots), per IP (20 an hour) and overall (300 confirmation emails an hour) through `Rails.cache`: with a null store nothing is counted, so give production a real cache store (Shiplog warns at boot otherwise). The subscribe POST carries no CSRF token and checks none: the pages carrying the form are served with ETags, so a cached page could hold a stale token, and nothing happens until the address confirms by email.

Every newsletter links a preferences page, reached through a token in the URL without an account, where a subscriber changes the language, unsubscribes, resubscribes (no new confirmation: the token proves the mailbox) or deletes their data. The token is rotated after each change there (the page continues with the new one; the link in the old email stops working, the next newsletter carries the new one). Unsubscribed rows stay as a suppression record; subscribing again through the form means confirming again. Schedule `Shiplog::PurgeNewsletterJob` weekly (see [Scheduling](#scheduling)): it deletes pending rows untouched for 30 days and delivery rows older than 180 days. `bin/rails shiplog:purge_newsletter` does the same.

**One person on both lists.** Recipients are merged at send time and deduplicated by lowercased email; when an address is on both lists, your user wins (its locale, its preferences link). Any unsubscribe removes the address from both.

**Sending.** On an approved announcement's admin page: "Send a test to <your address>" (`config.current_admin`'s email, in a chosen locale; works before approval) and "Send…", which opens a confirmation step with the recipient count per locale and sends through `Shiplog::SendNewsletterJob`. Send stays disabled, with the reasons on the page, until the announcement is approved, every configured locale has a current translation (no stale translation is ever sent), and `newsletter_from`, `newsletter_address` and an origin for links (`canonical_url`, else `action_mailer.default_url_options`) are set. The job renders the body once per locale and emails each recipient once: a `shiplog_newsletter_deliveries` row (unique on announcement and recipient key, no address) is inserted *before* the email leaves, 100 recipients at a time, and touched right before each send, so a retried job, two workers or a second click never send twice. This is at-most-once: a worker dying between the insert and the send leaves a pending row, never a duplicate. The page shows sent, failed and pending counts; "Retry failed" reclaims, in one statement, the failed rows and the rows left pending for more than an hour, and sends them again (the one case where a recipient may get the email twice, and you trigger it knowingly); a reclaimed row whose recipient is gone (unsubscribed, deleted) ends as failed with that reason. Failures are recorded as the exception's class and its message with anything address-like removed. One newsletter per announcement: a later Send only reaches recipients added since.

**Deliverability.** Send bulk mail through a separate stream, so a complaint never hurts your transactional email. With Postmark:

```ruby
config.newsletter_mailer_options = { message_stream: "broadcast" }
config.newsletter_batch_size     = 500   # the default; how many recipients a run claims at a time
```

`newsletter_mailer_options` is merged into every newsletter message (not the confirmation email, which is transactional and uses your default delivery settings): ActionMailer options (`delivery_method`, `delivery_method_options`) or headers your delivery gem reads. Also: set up SPF, DKIM and DMARC for the sending domain, keep the postal address in the footer, and let Postmark (or your provider) suppress bounces and complaints per stream. Shiplog adds `Precedence: bulk` and the one-click headers; it does no open or click tracking.

**Design.** `Shiplog::NewsletterMailer` builds an HTML part (one 600px table column, every style inline, absolute image URLs with width and alt, light colours that email clients invert sanely in dark mode: logo, "Monthly update · October 2026", title, the body, a button to the changelog, a footer with unsubscribe, preferences and the postal address) and a text part. The subject, title and body are the announcement's translation in the recipient's locale (English without one); the chrome uses Shiplog's I18n keys under `shiplog.newsletter` (en and es shipped). "View in browser" opens the announcement's page (`config.announcement_url`, called with the entry and the locale, when announcements are `:external`). The templates are `app/views/shiplog/newsletter_mailer/announcement.{html,text}.erb` and `confirmation.{html,text}.erb`: copy them into your app to change them, and `Shiplog::Markdown.to_html(text, styles: { "p" => "..." })` renders the body with inline styles. To preview locally, add the previews to `config/environments/development.rb` and open `/rails/mailers/shiplog/newsletter_mailer`:

```ruby
config.action_mailer.preview_paths << Shiplog::Engine.root.join("lib/shiplog/previews").to_s
```

**Admin.** The Newsletter page lists the subscribers (counts per locale and status, search, remove) and downloads them as CSV (cells that a spreadsheet would read as a formula are neutralised). Your own users are not listed: they are yours.

**What Shiplog stores, and consent.** In `shiplog_newsletter_subscribers`: the visitors who subscribed through its form (email, locale, the page they subscribed on, when they subscribed, confirmed and unsubscribed, the preferences token and a pending confirmation nonce), and one row per address that unsubscribed, your users' included: the suppression record that keeps the address out of future sends, holding the email and the time (no locale of yours, no source). Nothing else about your users, and no tracking of opens or clicks. Delivery rows (`shiplog_newsletter_deliveries`) keep the recipient key (`User/42` or `Subscriber/7`), the locale and the outcome, never the address; they are deleted with a subscriber's row, with the announcement, and after 180 days by the purge job. Log lines name recipient keys or a digest of the address, never the address; the rate-limit cache holds digests. A suppression row stays until the person deletes their data from the preferences page, an admin removes it, or your app calls `Shiplog::Newsletter.resubscribe`. No queued job carries an address: a test send is delivered in the request, a confirmation's job carries the subscriber's id, and the send job reads its recipients when it runs. Mention the newsletter in your privacy policy.

**Styling.** The form and pages use `shiplog-newsletter` with `__title`, `__hint`, `__form`, `__label`, `__input`, `__button` and `__notice`, all `config.classes` keys (`newsletter`, `newsletter_title`, ...). The honeypot sits in `shiplog-newsletter__trap`, which the bundled stylesheet moves out of view: keep a rule for it if you style the pages yourself.

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
| `entry_images` | `shiplog-entry__images` | The container of an entry's screenshots |
| `entry_image` | `shiplog-entry__image` | One screenshot (`img`) |

Values may be strings or arrays. The list is `Shiplog::Classes::KEYS`; assigning `config.classes` raises `ArgumentError` (listing the valid keys) for any other key, in every environment. String keys are accepted and normalised to symbols, and the hash is stored frozen. Texts come from I18n (`shiplog.roadmap.title`, `shiplog.roadmap.lede`, `shiplog.roadmap.*` (`parts`, `shipped_heading`, `full_changelog`, `footnote`, `suggest`), `shiplog.switcher.*`, `shiplog.changelog.*`, `shiplog.categories.feature` / `change`, `shiplog.date_format` (default `%-d %B %Y`, used for entry dates), `shiplog.columns.<column>_description`), so override them in your locale files.

### 4. Override the partials

Copy any view from the engine's `app/views/shiplog/` into your app with the same path and edit it. Each partial documents its locals in a comment on its first lines:

- `shiplog/_page.html.erb`, `shiplog/_page_header.html.erb`, `shiplog/_pagination.html.erb`, `shiplog/_empty.html.erb`
- `shiplog/_switcher.html.erb`
- `shiplog/roadmaps/_column.html.erb`, `shiplog/roadmaps/_card.html.erb`, `shiplog/roadmaps/_shipped.html.erb`
- `shiplog/changelogs/_month.html.erb`, `shiplog/changelogs/_entry.html.erb`, `shiplog/changelogs/_search.html.erb`
- `shiplog/newsletter/_form.html.erb` (the subscribe form), `shiplog/newsletter/_page.html.erb` (the confirm, preferences and unsubscribe pages' frame), and the emails in `shiplog/newsletter_mailer/`

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
