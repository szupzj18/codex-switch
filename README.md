# CodeX Switch

**Parallel multi-account manager for the OpenAI Codex CLI and Claude Code — zsh, bash and fish.**

Each account gets its own `CODEX_HOME` — separate sign-in, sessions, config
and usage quota. Accounts work **in parallel**: one account per terminal
(or per tmux/Herdr pane), no restart, no global "active account" that flips
every other window. Project directories can be bound to an account and
switch automatically on `cd`.

```text
$ cx usage
   NAME     PLAN    5H           7D           RESET  EXPIRES
 ● default  pro     –            ▓░░░░░   6%  4d9h   2026-11-02
   work     promax  –            ░░░░░░   0%  7d     2026-11-07
   side     team    ░░░░░░   0%  ▓▓░░░░  26%  1d15h  2026-10-17
```

`cx usage -v` expands each account into a block with its home directory,
20-cell usage bars and credits. Colors only appear on a terminal (honors
`NO_COLOR`; force with `CX_COLOR=always`).

## Claude Code accounts

The same shell can also hold Claude Code (subscription) accounts. Each one gets
its own `CLAUDE_CONFIG_DIR`, which Claude Code itself documents as the way to
stay signed in to several accounts: settings, history and the login are all
per directory (on macOS the Keychain entry is keyed by the directory path).

```shell
cx add --claude alt              # creates ~/.claude-alt, runs `claude auth login`
cx use alt                       # sets CLAUDE_CONFIG_DIR for this shell only
cx alt -p "hello"                # one-shot: runs claude under that account
cx bind alt                      # auto-switch for this directory, like Codex accounts
cx                               # TOOL column tells codex and claude accounts apart
```

Codex and Claude accounts share one namespace, so `cx work` always means one
thing. They are independent in a shell: `cx use work` (codex) and `cx use alt`
(claude) can be active together and the prompt shows both
(`[codex:work claude:alt]`). `cx use -` clears both.

Things worth knowing:

- Variables such as `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_API_KEY`,
  `CLAUDE_CODE_OAUTH_TOKEN` and `CLAUDE_CODE_USE_*` outrank a subscription
  login, and a set `ANTHROPIC_BASE_URL` redirects requests (for example to a
  local proxy). `cx use` warns when any of them is present; the one-shot form
  `cx alt ...` removes them for that run and pins `ANTHROPIC_BASE_URL` to
  `https://api.anthropic.com` if it was set.
- Account and plan come from `claude auth status`. Usage windows (5h / 7d) come
  from Claude Code's documented status-line data (`rate_limits`, claude.ai
  Pro/Max only): `cx hook install alt` wraps the account's status-line command
  in a small relay (`cx_statusline.py`) that saves those two windows to
  `<config dir>/.cx-usage.json` and then runs your original command unchanged.
  `cx usage` shows the cached values with their age; a window disappears once its
  reset time has passed. It reads no credentials and makes no network calls. The
  data only exists after the account has been used once with the relay installed.
  `cx hook install alt --dry-run` previews the change, a backup of `settings.json`
  is written first, and `cx hook remove alt` restores the original command.
  If the account has no status line yet, the relay shows a minimal one (model,
  context, 5h/7d). Claude Code hides most footer keyboard hints while any status
  line is configured, so `cx hook install` then asks for confirmation (or `--yes`)
  and `cx hook remove` deletes the line again.
- Only subscription (claude.ai) logins are isolated per directory. A Console
  sign-in without an API key is stored outside the config directory and is
  shared. Phase 1 does not manage third-party providers or API keys.
- Always register the directory with the same spelling: the Keychain entry name
  is derived from the exact path string (a trailing `/` makes a different one).
  `cx add` stores an absolute path without a trailing slash.

## Why

Codex CLI has no native multi-account support, and the built-in
`--profile` only layers config files — it shares one `auth.json` and cannot
switch sign-ins. Maintaining the feature is still an open upstream request.

Two design styles exist in the wild:

| Style | How it works | Parallel use? |
|---|---|---|
| Global switch (swap `auth.json`) | One active account machine-wide; restart clients after switching | No — every window flips |
| **`CODEX_HOME` isolation (this tool)** | One home directory per account; shell selects one | **Yes — different accounts per terminal** |

CodeX Switch is one small Python program (standard library only) plus a thin
layer for each shell: no wrapper around the
`codex` binary, no daemon, no proxy.

## Requirements

- zsh 5.3+, bash 3.2+ or fish 3+ (any of them; macOS defaults are fine)
- `python3` 3.8+ (standard library only — nothing to `pip install`)
- The official [Codex CLI](https://developers.openai.com/codex) on `PATH`

## Install

```shell
curl -fsSL https://raw.githubusercontent.com/szupzj18/codex-switch/main/install.sh | sh
```

Or clone and install locally:

```shell
git clone https://github.com/szupzj18/codex-switch.git
cd codex-switch && sh install.sh
```

Open a new terminal and run `cx help`.

The installer copies the program to `~/.codex-switch` and adds one `source`
block for each shell it finds: `~/.zshrc`, `~/.bashrc`, and
`~/.config/fish/conf.d/codex-switch.fish`. Upgrading from the zsh-only 0.1
needs nothing else: the same `source` line keeps working. Uninstall with
`sh uninstall.sh` (account data is never
deleted).

## Quick start

```shell
# Register an existing ~/.codex-* home (or create a fresh one and sign in)
cx setup                          # interactive first-run wizard
cx add work                       # creates ~/.codex-work, runs codex login
cx add side --device-auth         # headless sign-in flow
cx add client-acme --home ~/codex-homes/acme --no-login

cx                                # list accounts + emails + plan/expiry
cx usage                          # compact board with live 5h/7d usage bars
cx usage -v                       # detailed blocks: home, bars, credits
cx use work                       # switch this shell
codex                             # ...now runs as work
cx use -                          # back to default
cx work exec "explain this repo"  # one-shot, without switching the shell
```

`cx use` is scoped to the current shell — open another terminal and
`cx use side` there; both run at the same time on different accounts.

## Project bindings

Bind a repository to the account that owns it. Entering the directory (or
any subdirectory) switches automatically; leaving restores the account you
had before:

```shell
cd ~/code/company-api
cx bind work                      # bind current dir (or: cx bind work)
cd ~                              # restored automatically
cd ~/code/company-api             # switches to work again; RPROMPT shows [codex:work:auto]

cx binds                          # list bindings
cx unbind                         # remove the binding for the current dir
```

A manual `cx use` inside a bound directory wins until you leave it. Bindings
match by longest directory prefix, so nested projects can bind differently
from their parent.

## Commands

| Command | Description |
|---|---|
| `cx` / `cx ls` | List accounts, home directories, signed-in emails, plan and subscription expiry |
| `cx usage` | Compact board with live 5h/7d usage bars per account (queries chatgpt.com with each account's own token) |
| `cx usage -v` / `cx ls -v` | Detailed per-account blocks (home directory, 20-cell bars, credits) |
| `cx setup` | Interactive first-run wizard: adopt existing `~/.codex-*` homes, sign in, add accounts, bind this directory |
| `cx use <name>` / `cx use -` | Switch this shell to an account / back to default |
| `cx <name> [args...]` | One-shot invocation under that account (`codex`, or `claude` for a Claude account) |
| `cx login <name>` | (Re)run `codex login` for one account |
| `cx off` | Clear the switch in this shell |
| `cx add <name>` | Create a Codex account: new `CODEX_HOME` + sign-in |
| `cx hook install\|remove\|status <claude>` | Relay Claude Code's status-line `rate_limits` into a cache so `cx usage` can show 5h/7d (`--dry-run` previews) |
| `cx add --claude <name>` | Create a Claude Code subscription account: new `CLAUDE_CONFIG_DIR` + `claude auth login` |
| `cx add ... --home DIR` | Register an existing home directory instead |
| `cx add ... --no-login` / `--device-auth` | Skip login / use headless sign-in |
| `cx rm <name>` / `cx rm <name> --purge` | Unregister (data kept by default; confirm to delete) |
| `cx bind [name]` | Bind the current directory to an account |
| `cx unbind [dir]` | Remove a directory binding |
| `cx binds` | List project bindings |
| `cx version`, `cx help` | Version / help |

All commands and account names offer tab completion. The active account is
shown in the right prompt (`[codex:work]`, or `[codex:work:auto]` for a
directory binding).

## For AI agents

An agent-readable summary (commands, non-interactive usage, files, caveats) is
served at <https://szupzj18.github.io/codex-switch/llms.txt>.

## Shell support

| | zsh | bash | fish |
|---|---|---|---|
| `cx` commands, `cx use`, one-shot | yes | yes | yes |
| Auto-switch on `cd` (bindings) | `chpwd` hook | `PROMPT_COMMAND` | `--on-variable PWD` |
| Tab completion | yes | yes | yes |
| Prompt marker | right prompt, automatic | `$CX_PROMPT_TEXT` | `$CX_PROMPT_TEXT` |

The marker text (`[codex:work]`, `[codex:work:auto]`) is exposed as
`$CX_PROMPT_TEXT` in every shell. For bash: `PS1='$CX_PROMPT_TEXT \u@\h:\w\$ '`.
For fish: `function fish_right_prompt; echo $CX_PROMPT_TEXT; end`.

How it works: the shell function `cx` runs `cx_core.py`, which does all the
work and writes any environment changes it needs (`CODEX_HOME`, binding
state, prompt marker) to a temporary file that the wrapper then sources.
That is how one implementation serves every shell.

## Multiplexers (tmux / Herdr)

Because selection is just an environment variable, every pane is
independent:

```shell
# pane 1
cx use work && codex
# pane 2
cx use side && codex
```

A 2x2 grid with four accounts signed in at once works naturally.

## Files

```text
~/.config/codex-switch/accounts.tsv    registered accounts   <name>\t<codex home>
~/.config/codex-switch/claude-accounts.tsv  Claude Code accounts <name>\t<config dir>
~/.config/codex-switch/bindings.tsv    project bindings      <name>\t<project path>
~/.codex-switch/cx_core.py                  the program
~/.codex-switch/codex-switch.{zsh,bash,fish}  per-shell wrappers
~/.codex/  ~/.codex-<name>/        per-account Codex homes (untouched by CodeX Switch)
```

Override the registry location with `CX_CONFIG_DIR`.

On first run, `default` (`~/.codex`) is seeded automatically and existing
`~/.codex-*` homes that already contain an `auth.json` are registered.

## Notes

- `cx ls` decodes the email, plan and expiry from each account's JWT `id_token` locally; no
  token is ever printed or sent anywhere except to OpenAI by Codex itself.
- This tool never modifies anything inside the account homes — it only sets
  `CODEX_HOME` for the shell and tracks two small TSV files.
- VS Code extension and the Codex desktop app do not read `CODEX_HOME`;
  CodeX Switch manages the CLI only.

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

## Uninstall

```shell
sh uninstall.sh          # remove the rc source blocks
sh uninstall.sh --purge  # also remove ~/.codex-switch
```

Account homes and `~/.config/codex-switch` are kept; delete them yourself if
desired.

## License

[MIT](LICENSE)
