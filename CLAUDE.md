# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **chezmoi source directory** (`~/.local/share/chezmoi`) for bootstrapping and maintaining macOS machines (personal and work, split by `is_work`) and, secondarily, Linux machines for shell/CLI config only. There is no application code — every file here is either a *source* for a dotfile in `$HOME`, machine-provisioning data, or a script chezmoi runs during `apply`. The only automated verification is the CI workflow described below.

Editing a file here changes nothing on the machine until `chezmoi apply` runs.

## Common commands

```shell
chezmoi diff                  # preview what apply would change in $HOME
chezmoi apply -v              # apply; `apply --dry-run -v` rehearses
                              # (--dry-run without -v prints nothing at all)
chezmoi init -va              # re-prompt for config data + apply (fish abbr: cha)
chezmoi cd                    # cd into this directory (abbr: chc)
chezmoi update                # git pull + apply (abbr: chu)
chezmoi execute-template < f  # render a template against current data
chezmoi data                  # dump the template variables available
chezmoi add ~/.some/file      # import an existing dotfile into the source tree
```

Never hand-edit files in `$HOME` that chezmoi manages — edit the source here, then `apply`. Use `chezmoi add` to pull in an outside change.

Bootstrapping a fresh Mac is `scripts/setup` — Xcode CLT → Homebrew → chezmoi → `chezmoi init --apply`, and nothing else. **It requires a controlling terminal**: chezmoi reads init prompts from `/dev/tty` (not stdin), so with no tty `chezmoi init` fails *after* Homebrew is installed. The script checks `exec 3<>/dev/tty` up front and aborts with preseed instructions. Note this is about `/dev/tty`, not stdin — `curl … | bash` prompts fine from a terminal; the documented `"$(curl …)"` form is preferred only because it also keeps stdin a tty, keeping Homebrew's installer interactive. It is invoked via the curl one-liner in `readme.md` and is deliberately excluded from both `apply` (`.chezmoiignore.tmpl`) and `chezmoi diff` (`[diff] exclude` in `.chezmoi.toml.tmpl`). Anything that could live in a chezmoi script belongs in `.chezmoiscripts/`, not here — the bootstrap is intentionally the smallest thing that can run before chezmoi exists.

To rerun a package sync with removal of unlisted formulae: `BUNDLE_CLEANUP=1 chezmoi apply`.

## Source-file naming (chezmoi attribute prefixes)

Filenames encode the target path and permissions; renaming a file is a semantic change:

- `dot_` → leading `.` (`dot_gitconfig.tmpl` → `~/.gitconfig`)
- `private_` → mode 0600/0700 (`dot_config/private_fish/` → `~/.config/fish`, 0700)
- `.tmpl` → rendered as a Go text/template before writing
- `.chezmoiscripts/` → scripts executed during `apply`, never written into `$HOME`
- `run_onchange_` → rerun only when the rendered script content changes
- `run_onchange_after_` → runs after the file targets have been applied
- `run_once_` → runs a single time per machine, tracked in chezmoi's state DB
  (reset with `chezmoi state delete-bucket --bucket=scriptState`)

Three chezmoi-special directories carry no target of their own:

- `.chezmoidata/` → auto-loaded template data (`.packages`)
- `.chezmoitemplates/` → shared template bodies, pulled in via `includeTemplate`
- `.chezmoiremove` → targets to *delete* from `$HOME` on every apply

## Template data

Variables come from `.chezmoi.toml.tmpl`, which prompts once at `chezmoi init` and writes `~/.config/chezmoi/chezmoi.toml`:

| Variable | Source |
| --- | --- |
| `.name`, `.email` | prompt (`promptStringOnce`) |
| `.is_work` | prompt; gates work-vs-personal package sets |
| `.aws_profile` | prompt; exported as `AWS_PROFILE` in fish |
| `.homebrew_prefix` | derived from arch — `/opt/homebrew` on arm64, `/usr/local` on amd64 |
| `.packages` | `.chezmoidata/packages.yaml` (all files under `.chezmoidata/` are auto-loaded) |

Changing prompt defaults in `.chezmoi.toml.tmpl` has no effect on a machine that already answered them; `chezmoi init -va` re-prompts.

Guard macOS-only blocks with `{{ if eq .chezmoi.os "darwin" }}`; `config.fish.tmpl` and `tmux.conf.tmpl` both carry Linux branches. Reference Homebrew paths through `{{ .homebrew_prefix }}` rather than hardcoding them — but only where the path is genuinely Homebrew's. Code that should work on both OSes resolves binaries at runtime instead (`run_onchange_setup-shell.sh.tmpl` uses `command -v fish`).

## Adding software

Edit `.chezmoidata/packages.yaml` only. `.chezmoitemplates/Brewfile` renders that data into a Brewfile body; `dot_Brewfile.tmpl` pulls it in via `includeTemplate` so `~/.Brewfile` is a **chezmoi-managed target** — package changes appear as a real diff in `chezmoi diff`. `run_onchange_after_darwin-install-packages.sh.tmpl` then just runs `brew bundle --global`; it reruns because it embeds `{{ includeTemplate "Brewfile" . | sha256sum }}`, so it fires exactly when the rendered Brewfile changes. The `after_` prefix is load-bearing: it guarantees `~/.Brewfile` is written before `brew bundle` reads it.

Each of `taps`, `brews`, `casks`, `mas` is split into three tiers:

- `universal` — every machine
- `personal` — only when `is_work = false`
- `work` — only when `is_work = true`

`mas` entries are objects (`name` + numeric `id`); the App Store must be signed in before the first apply. `fisher` plugins live at the top level of `packages.yaml`, not under `darwin`, and install on every OS via `run_onchange_after_setup-fisher.sh.tmpl`.

Any formula from a non-official tap needs its tap listed under `taps` in the same tier. Homebrew 6 requires explicit trust for non-official taps and **silently ignores** formulae from untrusted ones, so an undeclared tap means the package just never installs on a fresh machine — with `brew bundle` still exiting 0. The install script therefore runs `brew trust --tap` for every tap it finds in the rendered Brewfile before bundling, and CI fails if a `user/repo/formula` entry has no matching `tap` line. Note trust state lives in `~/.homebrew/trust.json`, which chezmoi does not manage, so an already-working machine tells you nothing about a fresh one.

`BUNDLE_CLEANUP` is read at *runtime*, not template time — gating it in the template would change the rendered script body and pollute the `run_onchange_` hash.

## macOS defaults and security

`.macos` is a plain `defaults write` script, not a template, and it is not applied to `$HOME`. It is invoked by `run_onchange_setup-defaults.sh.tmpl`, which embeds `{{ include ".macos" | sha256sum }}` in a comment so that editing `.macos` changes the rendered script and retriggers it. Keep that hash line, and keep it on its own line — a `{{- ... -}}` trim there once swallowed the following statement into the comment. The script ends by restarting Dock/Finder/SystemUIServer/ControlCenter, so an apply visibly restarts UI elements.

Sudo-requiring system settings live separately in `run_onchange_darwin-security.sh.tmpl` (TouchID for sudo, application firewall, a FileVault *warning* that never aborts). They are kept out of `.macos` so that script can keep running unprivileged. These were previously inherited from strap.

`run_once_darwin-link-ssh.sh.tmpl` symlinks `~/.ssh` to iCloud Drive on personal machines only, and refuses to create a dangling link if iCloud has not synced.

## Shell

fish is the login shell; `run_onchange_setup-shell.sh.tmpl` registers it in `/etc/shells` and runs `chsh` (needs sudo). It is OS-agnostic — it resolves fish via `command -v`, not `homebrew_prefix`. Interactive config lives in `dot_config/private_fish/config.fish.tmpl` (abbreviations, `brew shellenv`, direnv/mise/cargo hooks); `conf.d/*.fish` files are auto-sourced and are the place for topic-scoped additions such as `wol.fish`.

**Do not generate completions into `~/.config/fish/completions/`.** That directory sorts first on `$fish_complete_path`, so anything written there shadows the current, package-manager-supplied completions in `$HOMEBREW_PREFIX/share/fish/vendor_completions.d/` — Homebrew already ships fish completions for docker, uv, uvx, bat, gh, rg, delta, chezmoi and more. An earlier version of this repo did exactly that and served nine-month-old copies as a result; `.chezmoiremove` now deletes those three files on every machine. The `generate_completions` function is an on-demand Linux fallback only: it writes to `~/.local/share/fish/vendor_completions.d/` and skips any command that already has a packaged completion.

Note that fisher installs into `~/.config/fish/{functions,completions,conf.d}` alongside chezmoi's managed files. chezmoi leaves unmanaged files alone, so the two coexist, but `chezmoi unmanaged ~/.config/fish` is worth checking before adding anything there.

## tmux

Plugins are declared as `@plugin` lines in `dot_config/tmux/tmux.conf.tmpl` and installed by `run_onchange_after_setup-tmux-plugins.sh.tmpl`, so `prefix + I` inside a live session is only ever needed to refresh by hand. tpm's `bin/install_plugins` does not need a running client — it runs `tmux start-server` itself, which sources the config and sets `TMUX_PLUGIN_MANAGER_PATH` — so an unattended `apply` can do the first install. The script embeds `{{ include "dot_config/tmux/tmux.conf.tmpl" | sha256sum }}` so it refires on any tmux.conf change, and the `after_` prefix guarantees the config is written before tpm reads it.

Because `~/.config/tmux/tmux.conf` exists, tpm puts plugins in `~/.config/tmux/plugins/`, **not** `~/.tmux/plugins/` — both the `run` line and the install script must agree on that path. On macOS tpm comes from the `tpm` formula and is run out of `{{ .homebrew_prefix }}/opt/tpm/share/tpm`; on Linux there is no package manager, so the script clones tpm into the plugin directory on first apply.

## Linux

Supported for shell and CLI config only: fish, tmux, git, and fisher plugins. There is deliberately no Linux package management. `.chezmoiignore.tmpl` excludes the macOS-only targets (`~/.Brewfile`, `~/.config/zed`, `~/Library`, `.macos`, `.mutagen.yml`) on non-darwin. Keep new GUI app configs out of Linux by adding them to that block.

## CI

`.github/workflows/ci.yml` runs `chezmoi apply --dry-run` on `macos-latest` and `ubuntu-latest` across both `is_work` values, parses the generated Brewfile, asserts the work/personal tiers do not leak into each other, and shellchecks the rendered `.chezmoiscripts/`. Three things about it are easy to get wrong and were each a real bug:

- **Every chezmoi call needs `-S <workspace>`.** `init --source=…` does not persist the source dir, and `CHEZMOI_SOURCE_DIR` is *not* read as config. Without `-S`, chezmoi finds no source dir and every check passes vacuously against zero managed targets — hence the explicit "verify the source dir was actually found" step.
- **`--promptString`/`--promptBool` are keyed by the prompt *text*, not the data key** — `"E-mail=…"` and `"Is it a work machine?=true"`, not `"email=…"` / `"is_work=true"`. Wrong keys do not error; chezmoi just tries to prompt and then fails on the missing tty.
- **`run:` values must not begin with a `"`.** YAML parses that as a quoted scalar and rejects the rest of the line. Putting `$HOME/.local/bin` on `$GITHUB_PATH` avoids the whole class.

The lint job runs on both OSes because a script guarded on the other OS renders empty and is skipped — ubuntu alone would never lint the darwin scripts. If you add a script, make sure its OS guard wraps the *whole* file so this holds.

## Conventions

Commit messages are short, lowercase, imperative (`add wol gpu abbrs`, `switch to ty lsp`).

`.chezmoiversion` pins a minimum chezmoi of 2.60.0.
