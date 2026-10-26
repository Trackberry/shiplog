# Shiplog

A mountable Rails engine that turns your GitHub issues, pull requests and commits into a public roadmap and changelog written for customers, not developers. An LLM that you supply drafts the plain-language text. Nothing is public until an admin approves it.

- **Roadmap**: issues labelled `public` appear in three columns (In progress, Coming soon, Later) once approved.
- **Changelog**: shipped features and small changes, grouped by month.
- **Admin**: drafts inbox, entry editing, a drag-and-drop roadmap board and a sync status page.

## Requirements

- Ruby 4.0 or newer
- Rails 8.1 or newer
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

`config.authorize_admin` is checked as well by the admin controllers, and a falsy result returns 403. Use it as defence in depth.

The public paths come from `config.roadmap_path` and `config.changelog_path`, read when routes are drawn.

### Customising the admin layout

The admin uses its own layout (`layouts/shiplog/admin`) and its own CSS and JS, served by the engine (and aware of your CSP nonce). To change it, create the same file in your app, which takes precedence over the engine's:

```erb
<%# app/views/layouts/shiplog/admin.html.erb %>
```

For smaller tweaks override a partial instead:

- `app/views/shiplog/admin/_custom_head.html.erb`: rendered inside `<head>` (extra stylesheets, favicon, ...).
- `app/views/shiplog/admin/_nav.html.erb`: the navigation bar.

Engine views use the engine's route helpers, so inside a host layout or partial rendered by a Shiplog controller use `main_app.` helpers for your own routes.

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
| `commit_types` | `["feat", "fix", "perf"]` | Conventional-commit types eligible for the changelog. |
| `rewriter` | `nil` | Callable that rewrites text with an LLM. See [The rewriter](#the-rewriter). |
| `product_name` | `nil` | Your product's name, used in the prompts. |
| `audience` | `nil` | Who your customers are, used in the prompts. |
| `tone` | `"Friendly, concise, no jargon. Address the customer as 'you'."` | Writing style used in the prompts. |
| `prompt_builder` | `nil` | Optional `->(kind:, context:) { String }` replacing the built-in prompts. `kind` is `"roadmap"`, `"feature"` or `"change"`. |
| `public_parent_controller` | `"ActionController::Base"` | Parent class of the public controllers. Read once when they load, so set it in the initializer. |
| `public_layout` | `"shiplog/application"` | Layout of the public pages. |
| `authorize_admin` | `->(controller) { true }` | Extra admin check; return false for a 403. |
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
- **Small changes**: the weekly scan looks at pull requests merged, and stored commits made, since the last scan (seven days on the first run). Commits are only considered when they are on the default branch and have no pull request, and their conventional-commit type (`feat:`, `fix(scope):`, ...) must be in `commit_types`.
- **Exclusions**: pull requests with an excluded label or an excluded author, commits from excluded authors, pull requests that belong to a feature's issue tree (the feature entry covers them), and anything that already has an entry.

## Approval workflow

Every entry starts as a **draft**. In the admin inbox you can edit the text, regenerate it, approve it or discard it. Only approved entries are public. Discarded entries are never proposed again but can be restored. If the GitHub text changes after a draft was written, the entry is flagged "GitHub text changed since this draft" and can be regenerated, and approved text is never replaced silently.

## Hosting notes

- Set `public_parent_controller` in an initializer (`config/initializers/shiplog.rb`). It is read once, when the engine's public controller class loads, so changing it later has no effect.
- Host layouts rendered by engine controllers must use `main_app.` route helpers (for example `main_app.root_path`), because the engine's own routes are the default inside them.
- If your host layout shows per-user content, add `etag { current_user&.id }` to the parent controller so cached responses are not shared between users.

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
