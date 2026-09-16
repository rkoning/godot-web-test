# Logistics Roguelike — web build

Godot 4 project that exports to the web and publishes to GitHub Pages whenever a
release is published. See [`one-pager.md`](one-pager.md) for the design.

## Layout

```
game/                          Godot project root (project.godot lives here)
  export_presets.cfg           the "Web" preset — tracked on purpose, CI needs it
.github/actions/godot-export/  composite action: install Godot, import, export, verify
.github/workflows/ci.yml       export on every push/PR, no deploy
.github/workflows/release.yml  export + deploy to Pages + attach zip to the release
```

## One-time setup

1. **Settings → Pages → Build and deployment → Source: GitHub Actions.**
   Without this the `deploy` job fails on the Pages API.
2. Nothing else. No secrets, no tokens — `deploy-pages` uses the workflow's OIDC
   identity and the release upload uses the built-in `GITHUB_TOKEN`.

## Publishing

Cut a GitHub release (tag + publish). That fires `release.yml`, which:

1. exports the `Web` preset headlessly with a pinned Godot version,
2. verifies the export actually produced `index.{html,js,wasm,pck}` — Godot can
   exit 0 having written a blank page,
3. deploys `build/` to Pages,
4. attaches `web-<tag>.zip` to the release, so every release is downloadable and
   reproducible independent of Pages.

`workflow_dispatch` runs the same thing manually.

## Threads are off, deliberately

Godot's threaded web export requires the `Cross-Origin-Opener-Policy` and
`Cross-Origin-Embedder-Policy` headers. **GitHub Pages cannot set response
headers**, so the preset sets `variant/thread_support=false` and the build runs
single-threaded. For a turn-based strategy game that costs nothing.

If you ever need threads, the options are: ship `coi-serviceworker.js` to
synthesize the headers, or move hosting to something that can set them
(itch.io, Cloudflare Pages, Netlify).

## Upgrading Godot

Bump `GODOT_VERSION` / `GODOT_RELEASE` in both workflows. The action downloads
the matching editor and export templates from `godotengine/godot-builds` and
caches them by version, so the first run after a bump is slower.

Keep the version in `game/project.godot`'s `config/features` in sync.

## Local export

```sh
cd game
godot --headless --import
godot --headless --export-release "Web" ../build/index.html
cd ../build && python3 -m http.server 8000
```
