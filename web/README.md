# Zorua web

A local dashboard for Zorua: accounts, 5h/7d usage, providers and directory bindings, with account management and a provider editor. Next.js and Tailwind CSS.
It is optional and separate from the Python program; it is not part of the release tarball.

- Data comes from `zorua usage --json` (run by the server, never by the browser). Tokens and provider keys are not in that output. A provider key reaches the page only when you press **show keys** in that provider's editor.
- Layout: a sidebar (overview, accounts, providers) and a content area. The overview shows accounts and providers in two columns; a provider or account opens as a page (`#/provider/<name>`, `#/account/<name>`). Dark by default, light follows the system; the **auto / light / dark** switch in the sidebar overrides it.
- Results are cached for 30 s and refreshed in the background, so the page opens at once. The refresh button forces a reload (at most one per 5 s).

## What you can do

| | runs |
|---|---|
| add an account (Codex or Claude Code), optionally start the sign-in | `zorua add [--claude] <name> --no-login`, then `zorua login <name>` |
| sign in again | `zorua login <name>`: the CLI opens your browser; the page shows the link it printed and the result |
| remove an account; optionally delete its data directory | `zorua rm <name> [--purge]` |
| add or remove a provider (key typed once, stored by zorua in its own `providers.json`) | `zorua provider add / rm` |
| view and edit a provider: base URL, key and the five model slots up front, the model catalog and all other env variables in collapsible sections. There is no save button: a field is saved when you leave it (a masked key is kept as is; **show keys** reads the real one; **copy** copies it without showing) | `zorua provider get [--reveal]`, `zorua provider put` (keeps `providers.json.bak`) |
| bind or unbind a directory | `zorua bind <name>` run inside that directory, `zorua unbind <dir>` |

Safety:

- The server binds to `127.0.0.1` and refuses requests whose `Host` is not loopback.
- Changes are `POST /api/action` only and need the same `Origin`, a JSON body and an `x-zorua-web` header, which a page on another site cannot send.
- Commands are started without a shell, with fixed argument lists; names, URLs and paths are validated first. Keys travel in an environment variable, not in arguments, and are scrubbed from error messages.
- Deleting data needs the account name typed, and is refused unless the directory is one Zorua created (`~/.codex-<name>`, `~/.claude-<name>`).
- A sign-in that does not finish is stopped after 10 minutes.

## Run

Needs Node 20+ and a Zorua with `--json` (`~/.zorua/zorua_core.py`).

```sh
cd web
npm ci
npm run build
npm start            # http://127.0.0.1:4747
```

`npm run dev` starts the development server on the same port. Set `ZORUA_CORE` to use another `zorua_core.py`.

## Keep it running (macOS)

```sh
sh launchd/zorua-web.sh install     # builds, then installs a LaunchAgent: starts now and at login
sh launchd/zorua-web.sh status
sh launchd/zorua-web.sh uninstall
```

A LaunchAgent does not inherit your shell's proxy variables, so `install` takes the proxy from `ZORUA_WEB_PROXY` (or your current `HTTPS_PROXY`) and writes it into the plist; it refuses to install without one, so usage requests never go out directly.
`ZORUA_WEB_PROXY=http://127.0.0.1:7897 sh launchd/zorua-web.sh install`
To change it later, edit `EnvironmentVariables` in `~/Library/LaunchAgents/org.zorua.web.plist` and reinstall.
Log: `~/Library/Logs/zorua-web.log`.

## Tests

```sh
npm run build
sh tests/run.sh      # isolated HOME and fake claude/codex; never touches your real accounts
```
