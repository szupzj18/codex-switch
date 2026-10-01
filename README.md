# CodeX Switch

**Parallel multi-account manager for the OpenAI Codex CLI, in zsh.**

Each account gets its own `CODEX_HOME` — separate sign-in, sessions, config
and usage quota. Accounts work **in parallel**: one account per terminal
(or per tmux/Herdr pane), no restart, no global "active account" that flips
every other window. Project directories can be bound to an account and
switch automatically on `cd`.

```text
$ cx
 codex accounts (* active in this shell, a auto-switch by directory)
 * default      ~/.codex           alice@gmail.com
   work         ~/.codex-work      alice@company.com
   side         ~/.codex-side      bob@gmail.com
```

## Why

Codex CLI has no native multi-account support, and the built-in
`--profile` only layers config files — it shares one `auth.json` and cannot
switch sign-ins. Maintaining the feature is still an open upstream request.

Two design styles exist in the wild:

| Style | How it works | Parallel use? |
|---|---|---|
| Global switch (swap `auth.json`) | One active account machine-wide; restart clients after switching | No — every window flips |
| **`CODEX_HOME` isolation (this tool)** | One home directory per account; shell selects one | **Yes — different accounts per terminal** |

CodeX Switch is a single dependency-free zsh script: no wrapper around the
`codex` binary, no daemon, no proxy.

## Requirements

- zsh 5.3+ (macOS default is fine)
- The official [Codex CLI](https://developers.openai.com/codex) on `PATH`
- `python3` optional — only used to decode the signed-in email for `cx ls`

## Install

```shell
curl -fsSL https://raw.githubusercontent.com/szupzj18/codex-switch/main/install.sh | zsh
```

Or clone and install locally:

```shell
git clone https://github.com/szupzj18/codex-switch.git
cd codex-switch && zsh install.sh
```

Open a new terminal and run `cx help`.

The installer adds one `source` block to `~/.zshrc` and copies the script to
`~/.codex-switch`. Uninstall with `zsh uninstall.sh` (account data is never
deleted).

## Quick start

```shell
# Register an existing ~/.codex-* home (or create a fresh one and sign in)
cx add work                       # creates ~/.codex-work, runs codex login
cx add side --device-auth         # headless sign-in flow
cx add client-acme --home ~/codex-homes/acme --no-login

cx                                # list accounts + signed-in emails
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
| `cx` / `cx ls` | List accounts, home directories and signed-in emails |
| `cx use <name>` / `cx use -` | Switch this shell to an account / back to default |
| `cx <name> [codex args...]` | One-shot invocation under that account |
| `cx login <name>` | (Re)run `codex login` for one account |
| `cx off` | Clear the switch in this shell |
| `cx add <name>` | Create an account: new `CODEX_HOME` + sign-in |
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
~/.config/codex-switch/bindings.tsv    project bindings      <name>\t<project path>
~/.codex-switch/codex-switch.zsh           the installed script
~/.codex/  ~/.codex-<name>/        per-account Codex homes (untouched by CodeX Switch)
```

Override the registry location with `CX_CONFIG_DIR`.

On first run, `default` (`~/.codex`) is seeded automatically and existing
`~/.codex-*` homes that already contain an `auth.json` are registered.

## Notes

- `cx ls` decodes the email from each account's JWT `id_token` locally; no
  token is ever printed or sent anywhere except to OpenAI by Codex itself.
- This tool never modifies anything inside the account homes — it only sets
  `CODEX_HOME` for the shell and tracks two small TSV files.
- VS Code extension and the Codex desktop app do not read `CODEX_HOME`;
  CodeX Switch manages the CLI only.

## Development

```shell
zsh -n codex-switch.zsh         # syntax check
zsh tests/smoke.zsh             # unit-style checks (isolated temp HOME, no network)
zsh tests/install-e2e.zsh       # full install journey (must run as root in a bare container)
```

Run the install E2E locally in a throwaway container:

```shell
docker run --rm -v "$PWD":/src:ro -w /src ubuntu:24.04 bash -c \
  "apt-get update -qq && apt-get install -y -qq zsh python3 && zsh tests/install-e2e.zsh"
```

It creates a fresh unprivileged user, runs `install.sh`, exercises every
command in a real interactive zsh (with a fake `codex` on `PATH`), checks the
no-python3 fallback, and verifies `uninstall.sh` leaves account data intact.

CI (`.github/workflows/smoke.yml`) runs both suites on Linux/zsh for every
push and pull request; the install E2E runs inside an `ubuntu:24.04`
container.

## Uninstall

```shell
zsh uninstall.sh          # remove the zshrc source block
zsh uninstall.sh --purge  # also remove ~/.codex-switch
```

Account homes and `~/.config/codex-switch` are kept; delete them yourself if
desired.

## License

[MIT](LICENSE)
