# Zorua

**Parallel multi-account manager for the OpenAI Codex CLI and Claude Code — zsh, bash and fish.**

> Zorua was called *CodeX Switch* (`codex-switch`, command `cx`) before 0.5.0. **The command is now `zorua`**;
> `cx` no longer exists. To upgrade, run the installer again: it replaces the old `~/.zshrc`/`~/.bashrc` block,
> copies your accounts and bindings from `~/.config/codex-switch` (the old files are kept
> as a backup) and refreshes the usage relay of Claude accounts. See *Migrating* below.

Each account gets its own `CODEX_HOME` — separate sign-in, sessions, config
and usage quota. Accounts work **in parallel**: one account per terminal
(or per tmux/Herdr pane), no restart, no global "active account" that flips
every other window. Project directories can be bound to an account and
switch automatically on `cd`.

```text
$ zorua usage
 Codex
   NAME     PLAN    5H           7D           RESET  EXPIRES
 ● default  pro     –            ▓░░░░░   6%  4d9h   2026-11-02
   work     promax  –            ░░░░░░   0%  7d     2026-11-07
   side     team    ░░░░░░   0%  ▓▓░░░░  26%  1d15h  2026-10-17

 Claude Code
   NAME  PLAN  5H           7D           RESET
   alt   max   ▓▓▓░░░  42%  ▓░░░░░   7%  4d9h

 ● this shell  ◆ auto-bound directory
 alt: Claude usage as of 3m ago (from its last session)
```

`zorua usage -v` expands each account into a block with its home directory,
20-cell usage bars and credits. Colors only appear on a terminal (honors
`NO_COLOR`; force with `ZORUA_COLOR=always`).

## Claude Code accounts

The same shell can also hold Claude Code (subscription) accounts. Each one gets
its own `CLAUDE_CONFIG_DIR`, which Claude Code itself documents as the way to
stay signed in to several accounts: settings, history and the login are all
per directory (on macOS the Keychain entry is keyed by the directory path).

```shell
zorua add --claude alt              # creates ~/.claude-alt, runs `claude auth login`
zorua use alt                       # sets CLAUDE_CONFIG_DIR for this shell only
zorua alt -p "hello"                # one-shot: runs claude under that account
zorua bind alt                      # auto-switch for this directory, like Codex accounts
zorua                               # accounts are listed in a "Codex" and a "Claude Code" section
```

Codex and Claude accounts share one namespace, so `zorua work` always means one
thing. They are independent in a shell: `zorua use work` (codex) and `zorua use alt`
(claude) can be active together and the prompt shows both
(`[codex:work claude:alt]`). `zorua use -` clears both.

Things worth knowing:

- Variables such as `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`,
  `CLAUDE_CODE_OAUTH_TOKEN` and `CLAUDE_CODE_USE_*` outrank a subscription
  login, and a set `ANTHROPIC_BASE_URL` redirects requests (for example to a
  local proxy). `zorua use` warns when any of them is present; the one-shot form
  `zorua alt ...` removes them for that run and pins `ANTHROPIC_BASE_URL` to
  `https://api.anthropic.com` if it was set.
- Account and plan come from `claude auth status`. Usage windows (5h / 7d) come
  from Claude Code's documented status-line data (`rate_limits`, claude.ai
  Pro/Max only): `zorua hook install alt` wraps the account's status-line command
  in a small relay (`zorua_statusline.py`) that saves those two windows to
  `<config dir>/.zorua-usage.json` and then runs your original command unchanged.
  `zorua usage` shows the cached values with their age; a window disappears once its
  reset time has passed. It reads no credentials and makes no network calls. The
  data only exists after the account has been used once with the relay installed.
  `zorua hook install alt --dry-run` previews the change, a backup of `settings.json`
  is written first, and `zorua hook remove alt` restores the original command.
  If the account has no status line yet, the relay shows a minimal one (model,
  context, 5h/7d). Claude Code hides most footer keyboard hints while any status
  line is configured, so `zorua hook install` then asks for confirmation (or `--yes`)
  and `zorua hook remove` deletes the line again.
  The command is written so it keeps working when settings are shared between
  machines (the script path uses `$HOME`) and it falls back to your original
  command if the relay or python3 is missing, so a status line never breaks.
  `zorua hook status` lists every Claude account, `zorua hook remove --all` restores
  them all, and `sh uninstall.sh --purge` does that automatically.
- Only subscription (claude.ai) logins are isolated per directory. A Console
  sign-in without an API key is stored outside the config directory and is
  shared. Phase 1 does not manage third-party providers or API keys.
- Always register the directory with the same spelling: the Keychain entry name
  is derived from the exact path string (a trailing `/` makes a different one).
  `zorua add` stores an absolute path without a trailing slash.

## Why

Codex CLI has no native multi-account support, and the built-in
`--profile` only layers config files — it shares one `auth.json` and cannot
switch sign-ins. Maintaining the feature is still an open upstream request.

Two design styles exist in the wild:

| Style | How it works | Parallel use? |
|---|---|---|
| Global switch (swap `auth.json`) | One active account machine-wide; restart clients after switching | No — every window flips |
| **`CODEX_HOME` isolation (this tool)** | One home directory per account; shell selects one | **Yes — different accounts per terminal** |

Zorua is one small Python program (standard library only) plus a thin
layer for each shell: no wrapper around the
`codex` binary, no daemon, no proxy.

## Requirements

- zsh 5.3+, bash 3.2+ or fish 3+ (any of them; macOS defaults are fine)
- `python3` 3.8+ (standard library only — nothing to `pip install`)
- The official [Codex CLI](https://developers.openai.com/codex) on `PATH`

## Install

```shell
curl -fsSL https://raw.githubusercontent.com/szupzj18/zorua/main/install.sh | sh
```

Or clone and install locally:

```shell
git clone https://github.com/szupzj18/zorua.git
cd zorua && sh install.sh
```

Open a new terminal and run `zorua help`.

To install a specific release instead of `main`, pin it with `ZORUA_REF`:

```shell
curl -fsSL https://raw.githubusercontent.com/szupzj18/zorua/main/install.sh | ZORUA_REF=v0.5.0 sh
```

Each [release](https://github.com/szupzj18/zorua/releases) also ships a tarball
(`zorua-<version>.tar.gz`, usable with `sh install.sh` after extracting it) and a
`SHA256SUMS` file.

The installer copies the program to `~/.zorua` and adds one `source`
block for each shell it finds: `~/.zshrc`, `~/.bashrc`, and
`~/.config/fish/conf.d/zorua.fish`. Upgrading from the zsh-only 0.1
needs nothing else: the same `source` line keeps working. Uninstall with
`sh uninstall.sh` (account data is never
deleted).

## Quick start

```shell
# Register an existing ~/.codex-* home (or create a fresh one and sign in)
zorua setup                          # interactive first-run wizard
zorua add work                       # creates ~/.codex-work, runs codex login
zorua add side --device-auth         # headless sign-in flow
zorua add client-acme --home ~/codex-homes/acme --no-login

zorua                                # list accounts + emails + plan/expiry
zorua usage                          # compact board with live 5h/7d usage bars
zorua usage -v                       # detailed blocks: home, bars, credits
zorua use work                       # switch this shell
codex                                # ...now runs as work
zorua use -                          # back to default
zorua work exec "explain this repo"  # one-shot, without switching the shell
```

`zorua use` is scoped to the current shell — open another terminal and
`zorua use side` there; both run at the same time on different accounts.

## Project bindings

Bind a repository to the account that owns it. Entering the directory (or
any subdirectory) switches automatically; leaving restores the account you
had before:

```shell
cd ~/code/company-api
zorua bind work                      # bind current dir (or: zorua bind work)
cd ~                              # restored automatically
cd ~/code/company-api             # switches to work again; RPROMPT shows [codex:work:auto]

zorua binds                          # list bindings
zorua unbind                         # remove the binding for the current dir
```

A manual `zorua use` inside a bound directory wins until you leave it. Bindings
match by longest directory prefix, so nested projects can bind differently
from their parent.

## Commands

| Command | Description |
|---|---|
| `zorua` / `zorua ls` | List accounts, home directories, signed-in emails, plan and subscription expiry |
| `zorua usage` | Compact board with live 5h/7d usage bars per account (queries chatgpt.com with each account's own token) |
| `zorua usage -v` / `zorua ls -v` | Detailed per-account blocks (home directory, 20-cell bars, credits) |
| `zorua setup` | Interactive first-run wizard: adopt existing `~/.codex-*` homes, sign in, add accounts, bind this directory |
| `zorua use <name>` / `zorua use -` | Switch this shell to an account / back to default |
| `zorua <name> [args...]` | One-shot invocation under that account (`codex`, or `claude` for a Claude account) |
| `zorua login <name>` | (Re)run `codex login` for one account |
| `zorua off` | Clear the switch in this shell |
| `zorua add <name>` | Create a Codex account: new `CODEX_HOME` + sign-in |
| `zorua hook install\|remove\|status <claude>` | Relay Claude Code's status-line `rate_limits` into a cache so `zorua usage` can show 5h/7d (`--dry-run` previews) |
| `zorua add --claude <name>` | Create a Claude Code subscription account: new `CLAUDE_CONFIG_DIR` + `claude auth login` |
| `zorua add ... --home DIR` | Register an existing home directory instead |
| `zorua add ... --no-login` / `--device-auth` | Skip login / use headless sign-in |
| `zorua rm <name>` / `zorua rm <name> --purge` | Unregister (data kept by default; confirm to delete) |
| `zorua bind [name]` | Bind the current directory to an account |
| `zorua unbind [dir]` | Remove a directory binding |
| `zorua binds` | List project bindings |
| `zorua version`, `zorua help` | Version / help |

All commands and account names offer tab completion. The active account is
shown in the right prompt (`[codex:work]`, or `[codex:work:auto]` for a
directory binding).

## For AI agents

An agent-readable summary (commands, non-interactive usage, files, caveats) is
served at <https://szupzj18.github.io/zorua/llms.txt>.

## Shell support

| | zsh | bash | fish |
|---|---|---|---|
| `zorua` commands, `zorua use`, one-shot | yes | yes | yes |
| Auto-switch on `cd` (bindings) | `chpwd` hook | `PROMPT_COMMAND` | `--on-variable PWD` |
| Tab completion | yes | yes | yes |
| Prompt marker | right prompt, automatic | `$ZORUA_PROMPT_TEXT` | `$ZORUA_PROMPT_TEXT` |

The marker text (`[codex:work]`, `[codex:work:auto]`) is exposed as
`$ZORUA_PROMPT_TEXT` in every shell. For bash: `PS1='$ZORUA_PROMPT_TEXT \u@\h:\w\$ '`.
For fish: `function fish_right_prompt; echo $ZORUA_PROMPT_TEXT; end`.

How it works: the shell function `zorua` runs `zorua_core.py`, which does all the
work and writes any environment changes it needs (`CODEX_HOME`, binding
state, prompt marker) to a temporary file that the wrapper then sources.
That is how one implementation serves every shell.

## Multiplexers (tmux / Herdr)

Because selection is just an environment variable, every pane is
independent:

```shell
# pane 1
zorua use work && codex
# pane 2
zorua use side && codex
```

A 2x2 grid with four accounts signed in at once works naturally.

## Files

```text
~/.config/zorua/accounts.tsv    registered accounts   <name>\t<codex home>
~/.config/zorua/claude-accounts.tsv  Claude Code accounts <name>\t<config dir>
~/.config/zorua/bindings.tsv    project bindings      <name>\t<project path>
~/.zorua/zorua_core.py                  the program
~/.zorua/zorua.{zsh,bash,fish}  per-shell wrappers
~/.codex/  ~/.codex-<name>/        per-account Codex homes (untouched by Zorua)
```

Override the registry location with `ZORUA_CONFIG_DIR`.

On first run, `default` (`~/.codex`) is seeded automatically and existing
`~/.codex-*` homes that already contain an `auth.json` are registered.

## Notes

- `zorua ls` decodes the email, plan and expiry from each account's JWT `id_token` locally; no
  token is ever printed or sent anywhere except to OpenAI by Codex itself.
- This tool never modifies anything inside the account homes — it only sets
  `CODEX_HOME` for the shell and tracks two small TSV files.
- VS Code extension and the Codex desktop app do not read `CODEX_HOME`;
  Zorua manages the CLI only.

## Development

```shell
zsh tests/smoke.zsh             # unit-style checks per shell (isolated temp HOME, no network)
bash tests/smoke.bash
fish tests/smoke.fish
zsh tests/install-e2e.zsh       # full install journey (must run as root in a bare container)
```

Run the install E2E locally in a throwaway container:

```shell
docker run --rm -v "$PWD":/src:ro -w /src ubuntu:24.04 bash -c \
  "apt-get update -qq && apt-get install -y -qq zsh fish python3 && zsh tests/install-e2e.zsh"
```

It creates a fresh unprivileged user, runs `install.sh`, exercises the
commands in real interactive zsh, bash and fish shells (with a fake `codex`
on `PATH`), checks the message shown when python3 is missing, and verifies
`uninstall.sh` leaves account data intact.

CI (`.github/workflows/smoke.yml`) runs every suite for each push and pull
request (Python 3.8 and 3.12); the install E2E runs inside an `ubuntu:24.04`
container.

## Releasing

Releases are cut by pushing a tag; `.github/workflows/release.yml` does the rest:

1. Bump `VERSION` in `zorua_core.py` and merge it to `main` through a PR.
2. `git tag v0.5.0 && git push origin v0.5.0` on that commit. Tags with a suffix
   such as `v0.6.0-rc1` are published as pre-releases.
3. The workflow runs the full test suite (zsh, bash, fish, Python 3.8 and 3.12, install
   E2E), fails if the tag does not match `VERSION`, builds the tarball and
   `SHA256SUMS`, checks that the tarball installs and prints the right version, then
   creates the GitHub Release with generated notes and attaches `install.sh`.

## Uninstall

```shell
sh uninstall.sh          # remove the rc source blocks
sh uninstall.sh --purge  # also remove ~/.zorua
```

Account homes and `~/.config/zorua` are kept; delete them yourself if
desired.

## Migrating from CodeX Switch / the `cx` command

Run the installer once (`curl -fsSL https://raw.githubusercontent.com/szupzj18/zorua/main/install.sh | sh`).
It removes the old `# >>> codex-switch >>>` block from `~/.zshrc` / `~/.bashrc` (and
`conf.d/codex-switch.fish`), installs into `~/.zorua`, copies the registry to
`~/.config/zorua` and points Claude accounts' usage relay at the new location.
Nothing inside your account homes changes. Afterwards you may delete `~/.codex-switch`
and `~/.config/codex-switch`. The old GitHub address redirects to this repository.

Since 0.5.0 the command is `zorua` (it was `cx`). Rename it in your own scripts and
aliases; if you want the short form back, add `alias cx=zorua` yourself. Environment
variables moved from `CX_*` to `ZORUA_*` (`ZORUA_CONFIG_DIR`, `ZORUA_HOME`, `ZORUA_COLOR`,
`$ZORUA_PROMPT_TEXT`); `CX_CONFIG_DIR`, `CX_HOME` and `CX_COLOR` are still honoured.
Re-running the installer also removes the old `cx_*.py` files and rewrites the Claude
status-line relay to the new script name.

## License

[MIT](LICENSE)

---

Zorua is an independent project. The name is a nod to the Pokémon of the same name
(an illusion fox that takes on other forms); it is not affiliated with or endorsed by
Nintendo, Game Freak, Creatures or The Pokémon Company. Codex is a product of OpenAI and
Claude Code of Anthropic; this tool is not affiliated with either.
