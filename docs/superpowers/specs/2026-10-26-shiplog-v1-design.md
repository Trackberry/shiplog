# Shiplog v1 — Design

Source: GitHub issue #1. Decisions below were confirmed with the maintainer on 2026-10-26.

## Goal

A mountable Rails engine that turns GitHub issues, pull requests and commits into a
public roadmap and changelog written for non-developer customers. An LLM drafts the
plain-language text; nothing is public until an admin approves it. First host: Trackberry.

## Decisions

| Topic | Decision |
|---|---|
| Sync | Both: GitHub webhooks for freshness + scheduled sync to reconcile. |
| GitHub API | GraphQL v4 over `Net::HTTP` (no Octokit). Only GraphQL exposes PR↔issue closing links. |
| Auth to GitHub | `config.github_token` — a String or a callable (so a GitHub App installation token can be minted per call). |
| LLM | Host-supplied callable: `config.rewriter = ->(prompt) { "...model output..." }`. No LLM dependency in the gem. |
| Repos | Several repos per install (`config.repositories`). Sub-issues may cross repos (same owner). |
| Storage | Host database, tables prefixed `shiplog_`. PostgreSQL (jsonb). |
| Columns | Derived from GitHub state, admin can pin an item to a column and reorder by drag and drop. |
| Changelog vs Trackberry `learn/news` | Separate. Revisit after v1. |
| Admin | GoodJob pattern: own controllers on `ActionController::Base`, own layout and assets served by the engine, host protects the mount with a route constraint (`authenticate :user, ->(u) { u.admin? }`) and may override `layouts/shiplog/admin.html.erb`. |
| Versions | Ruby >= 4.0, Rails >= 8.1. |

## Mounting

Two engines in one gem, so the admin can be wrapped in host authentication like GoodJob
while the public pages and the webhook stay open:

```ruby
# host config/routes.rb
mount Shiplog::Engine => "/"                    # /roadmap, /changelog, /shiplog/github/webhook
authenticate :user, ->(user) { user.admin? } do
  mount Shiplog::Admin::Engine => "/admin/shiplog"
end
```

- `Shiplog::Engine` — `isolate_namespace Shiplog`. Public roadmap and changelog, webhook endpoint, asset endpoint.
- `Shiplog::Admin::Engine` — `isolate_namespace Shiplog::Admin`. Drafts inbox, entry editing, roadmap board, sync status.
- Paths of the public pages come from `config.roadmap_path` / `config.changelog_path` (default `roadmap` / `changelog`), read when routes are drawn.
- Defence in depth: `config.authorize_admin = ->(controller) { true }` is also checked by the admin base controller (returns 403 when false).

## Configuration

```ruby
Shiplog.configure do |config|
  config.repositories    = %w[Trackberry/trackberry Trackberry/trackberry-ios]
  config.github_token    = -> { Rails.application.credentials.dig(:github, :shiplog_token) }
  config.webhook_secret  = Rails.application.credentials.dig(:github, :shiplog_webhook_secret)

  config.public_label    = "public"                       # only issues with it reach the roadmap
  config.soon_labels     = %w[soon]                       # → "Coming soon"
  config.excluded_labels = %w[internal dependencies refactor chore]
  config.excluded_authors = [/\[bot\]\z/]                 # dependabot[bot], github-actions[bot]
  config.commit_types    = %w[feat fix perf]              # conventional-commit types eligible for the changelog

  config.rewriter        = ->(prompt) { Ai::Registry.default.complete(prompt) }
  config.product_name    = "Trackberry"
  config.audience        = "importers and exporters of fresh produce"
  config.tone            = "Friendly, concise, no jargon. Address the customer as 'you'."
  config.prompt_builder  = nil                            # optional ->(kind:, context:) { String } to replace the built-in prompts

  config.public_parent_controller = "ActionController::Base"
  config.public_layout   = "shiplog/application"
  config.authorize_admin = ->(controller) { true }
  config.current_admin   = ->(controller) { controller.try(:current_user)&.try(:email) }
  config.roadmap_path    = "roadmap"
  config.changelog_path  = "changelog"
end
```

## Data model

All tables prefixed `shiplog_`. GitHub objects are keyed by their GraphQL `node_id`.

- **Repository** — `full_name` (unique), `synced_at`, `sync_cursor` (timestamp of the newest `updatedAt` seen), `changes_scanned_at` (end of the last weekly scan window), `last_error`.
- **Issue** — `repository_id`, `node_id` (unique), `number`, `title`, `body`, `state` (open/closed), `state_reason`, `labels` (jsonb array of names), `milestone_title`, `assignees_count`, `parent_node_id`, `url`, `github_created_at`, `github_updated_at`, `closed_at`, `pinned_column` (nullable: in_progress/coming_soon/later), `position` (nullable int).
- **PullRequest** — `repository_id`, `node_id` (unique), `number`, `title`, `body`, `state` (open/closed/merged), `merged_at`, `author_login`, `labels`, `url`, `github_updated_at`.
- **IssueLink** — `issue_node_id`, `pull_request_node_id` (unique pair). No FKs: either side may be in a repo that isn't synced yet. Rebuilt for an issue/PR each time it's imported.
- **Commit** — `repository_id`, `sha` (unique per repo), `message`, `author_login`, `committed_at`, `url`. Only commits on the default branch with no associated PR are stored.
- **Entry** — public text.
  - `kind`: `roadmap` (an issue on the roadmap), `feature` (shipped parent issue), `change` (small merged PR or commit).
  - `status`: `draft`, `approved`, `discarded`.
  - `subject` (polymorphic: Issue, PullRequest, Commit), unique on `[subject_type, subject_id, kind]`.
  - `title`, `body`, `source_digest` (SHA256 of the source title+body at draft time), `rewritten_at`, `rewrite_error`.
  - `released_on` (date, for changelog ordering), `approved_at`, `approved_by`, `discard_reason`.
- **WebhookDelivery** — `delivery_id` (unique), `event`, `action`, `repository_full_name`, `received_at`, `processed_at`, `error`.

## Rules

**Public issue** — has `config.public_label`.

**Roadmap item** — a public, open issue whose parent is not a public issue (children of a public parent are folded into it). It is visible on the public roadmap only when its `roadmap` entry is approved. It disappears from the roadmap once closed.

**Column** (first match wins):
1. `pinned_column` if set by an admin.
2. `in_progress` — the issue or any descendant has an open linked PR, or the issue has assignees.
3. `coming_soon` — has a milestone or a `soon_labels` label.
4. `later`.

Order within a column: `position` (nulls last), then `github_updated_at` desc. Dragging a card on the admin board pins it to the target column and rewrites `position` for that column. "Unpin" clears both.

**Shipped feature** — a public top-level issue closed with `state_reason = COMPLETED` that has at least one merged linked PR on itself or a descendant (pull requests are the source of truth). Its `feature` entry is drafted when that becomes true. `released_on` = newest `merged_at` among those PRs.

**Small change** — the weekly scan considers PRs merged in the window and stored commits in the window, then skips:
- PRs carrying an excluded label, or authored by an excluded author;
- PRs linked to any issue in a public issue tree (the feature entry covers them);
- commits whose conventional-commit type is not in `commit_types`, or from excluded authors;
- anything that already has an entry.

Each remaining candidate gets a `change` draft. If the rewriter says it isn't customer-facing, the entry is stored as `discarded` with `discard_reason = "Not customer-facing (suggested by AI)"`. It is not proposed again, and an admin can restore it.

**Feature material** — issue bodies written with the shipped issue form are split into `### Problem`, `### Before`, `### After` sections (`_No response_` → nil). Sub-issue titles and linked PR titles are added to the prompt context.

**Source changed** — if the subject's current title+body digest differs from `source_digest`, the admin UI flags the entry ("GitHub text changed since this draft") and offers "Regenerate". Approved text is never silently replaced.

## Rewriting

`Shiplog::Rewriter` builds a prompt (or calls `config.prompt_builder`), calls `config.rewriter`, and parses JSON out of the reply:

```json
{"title": "...", "body": "...", "customer_facing": true}
```

It extracts the first `{…}` block, so models that wrap JSON in prose or fences still work. If there is no rewriter, the output can't be parsed, or the call raises, the entry keeps the original GitHub text and stores `rewrite_error`. Admins see this and can edit or regenerate. Rewrites run in `Shiplog::RewriteEntryJob`, never inside a request or webhook.

## Sync

- `Shiplog::SyncJob` (schedule every 15 min–1 h): for each configured repo, page `repository.issues(filterBy: {since: cursor}, orderBy: UPDATED_AT ASC)` and `repository.pullRequests(orderBy: UPDATED_AT DESC)` until older than the cursor. Upsert records and links, then run `Shiplog::Drafter` (create missing roadmap/feature drafts). The first run has no cursor and backfills everything.
- `Shiplog::ScanChangesJob` (schedule weekly): fetch default-branch commits since the last scan (`history(since:)` with `associatedPullRequests(first: 1)`), store those without a PR, and draft `change` entries.
- `Shiplog::RefreshJob(repository_full_name, kind, number)`: refetch one issue or PR by number (webhook path).
- Webhook `POST /shiplog/github/webhook`:
  - Verify `X-Hub-Signature-256` (HMAC-SHA256 of the raw body, `secure_compare`) → 401 if it fails.
  - Record the `X-GitHub-Delivery` id, which makes redeliveries no-ops.
  - Handle events: `issues`, `pull_request` and `sub_issues` (both sides) for configured repos.
  - Enqueue `RefreshJob` and respond 202. `ping` → 200. Anything else → 202 and ignored.
  - Because we always refetch the current state, out-of-order deliveries are harmless.
- GitHub errors: `Shiplog::Github::RateLimited` (retry at reset), `Shiplog::Github::Error`. The error is stored on `Repository#last_error` and shown in admin.

## UI

**Public** (host layout configurable, plain semantic HTML with `shiplog-` BEM classes and an optional default stylesheet):
- `/roadmap` — three columns, each card shows its approved title and body. No dates.
- `/changelog` — approved `feature` and `change` entries grouped by month (`released_on`), newest first. Feature entries are shown more prominently. 30 entries per page with `?page=`.

**Admin** (own layout, own CSS/JS served by the engine, CSP-nonce aware, overridable like GoodJob):
- Drafts inbox — filter by status/kind. Each row has its source link, "source changed" and rewrite-error badges, and approve/discard/restore actions.
- Entry edit — title/body form, source GitHub text side by side, Regenerate, Approve, Discard.
- Roadmap board — every roadmap item including unapproved ones (badged), in three columns. Supports drag and drop through a small vanilla ES module that does a `PATCH` with the column and ordered ids. A per-card column select + "Move" button is the no-JS fallback. Unpin.
- Sync — repositories with last sync/error, "Sync now", recent webhook deliveries.

## Also shipped

- Install generator: copies migrations and the initializer, adds the route snippet, and writes `.github/ISSUE_TEMPLATE/shiplog-feature.yml` (an issue form with Problem / Before / After fields and the `public` label).
- README covering setup, the GitHub token scopes needed (Issues + Pull requests + Contents read; Metadata), webhook setup, cron schedule examples (GoodJob, Solid Queue) and the Trackberry-style admin layout override.
- GitHub Actions CI: Postgres service, Ruby 4.0, Rails 8.1, RuboCop (rubocop-rails-omakase).

## Not in v1

Monthly email data, RSS/JSON feed, multiple languages, GitHub Projects status, wiring into Trackberry (separate PR in the trackberry repo).
