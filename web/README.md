# Zorua web

A local, read-only dashboard for Zorua: accounts, 5h/7d usage and providers. Next.js and Tailwind CSS.
It is optional and separate from the Python program; it is not part of the release tarball.

- Data comes from `zorua usage --json` (run by the server, never by the browser). Tokens and provider keys are not in that output and never reach the page.
- The server binds to `127.0.0.1` and refuses requests whose `Host` is not loopback.
- Nothing can be changed from the page.
- Results are cached for 30 s and refreshed in the background, so the page opens at once. The refresh button forces a reload (at most one per 5 s).

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
