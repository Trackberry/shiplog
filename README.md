# Shiplog

A Rails engine that turns your GitHub issues and pull requests into a public roadmap and changelog your customers can actually read.

Work in progress — see #1.

## Hosting notes

- Set `public_parent_controller` in an initializer (`config/initializers/shiplog.rb`). It is read once, when the engine's public controller class loads, so changing it later has no effect.
- Host layouts rendered by engine controllers must use `main_app.` route helpers (for example `main_app.root_path`), because the engine's own routes are the default inside them.
- If your host layout shows per-user content, add `etag { current_user&.id }` to the parent controller so cached responses are not shared between users.
