# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **chezmoi source directory** (`~/.local/share/chezmoi`) for bootstrapping and maintaining a macOS machine. There is no build, no tests, and no application code — every file here is either a *source* for a dotfile in `$HOME`, machine-provisioning data, or a script chezmoi runs during `apply`.

Editing a file here changes nothing on the machine until `chezmoi apply` runs.

## Common commands

```shell
chezmoi diff                  # preview what apply would change in $HOME
chezmoi apply -v              # apply (add --dry-run to rehearse)
chezmoi init -va              # re-prompt for config data + apply (fish abbr: cha)
chezmoi cd                    # cd into this directory (abbr: chc)
chezmoi update                # git pull + apply (abbr: chu)
chezmoi execute-template < f  # render a template against current data
chezmoi data                  # dump the template variables available
chezmoi add ~/.some/file      # import an existing dotfile into the source tree
```

Never hand-edit files in `$HOME` that chezmoi manages — edit the source here, then `apply`. Use `chezmoi add` to pull in an outside change.

Bootstrapping a fresh Mac is `scripts/setup` — Xcode CLT → Homebrew → chezmoi → `chezmoi init --apply`, and nothing else. It is invoked via the curl one-liner in `readme.md` and is deliberately excluded from both `apply` (`.chezmoiignore.tmpl`) and `chezmoi diff` (`[diff] exclude` in `.chezmoi.toml.tmpl`). Anything that could live in a chezmoi script belongs in `.chezmoiscripts/`, not here — the bootstrap is intentionally the smallest thing that can run before chezmoi exists.

To rerun a package sync with removal of unlisted formulae: `BUNDLE_CLEANUP=1 chezmoi apply`.

## Source-file naming (chezmoi attribute prefixes)

Filenames encode the target path and permissions; renaming a file is a semantic change:

- `dot_` → leading `.` (`dot_gitconfig.tmpl` → `~/.gitconfig`)
- `private_` → mode 0600/0700 (`dot_config/private_fish/` → `~/.config/fish`, 0700)
- `.tmpl` → rendered as a Go text/template before writing
- `.chezmoiscripts/` → scripts executed during `apply`, never written into `$HOME`
- `run_onchange_` → rerun only when the rendered script content changes
- `run_onchange_after_` → runs after the file targets have been applied

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

Always reference Homebrew paths through `{{ .homebrew_prefix }}` rather than hardcoding, and guard macOS-only blocks with `{{ if eq .chezmoi.os "darwin" }}` — several templates (fish, tmux) also have Linux branches.

## Adding software

Edit `.chezmoidata/packages.yaml` only. `.chezmoitemplates/Brewfile` renders that data into a Brewfile body; `dot_Brewfile.tmpl` pulls it in via `includeTemplate` so `~/.Brewfile` is a **chezmoi-managed target** — package changes appear as a real diff in `chezmoi diff`. `run_onchange_after_darwin-install-packages.sh.tmpl` then just runs `brew bundle --global`; it reruns because it embeds `{{ includeTemplate "Brewfile" . | sha256sum }}`, so it fires exactly when the rendered Brewfile changes. The `after_` prefix is load-bearing: it guarantees `~/.Brewfile` is written before `brew bundle` reads it.

Each of `brews`, `casks`, `mas` is split into three tiers:

- `universal` — every machine
- `personal` — only when `is_work = false`
- `work` — only when `is_work = true`

`mas` entries are objects (`name` + numeric `id`); the App Store must be signed in before the first apply. `fisher` plugins live at the top level of `packages.yaml`, not under `darwin`, and install on every OS via `run_onchange_after_setup-fisher.sh.tmpl`.

`BUNDLE_CLEANUP` is read at *runtime*, not template time — gating it in the template would change the rendered script body and pollute the `run_onchange_` hash.

## macOS defaults and security

`.macos` is a plain `defaults write` script, not a template, and it is not applied to `$HOME`. It is invoked by `run_onchange_setup-defaults.sh.tmpl`, which embeds `{{ include ".macos" | sha256sum }}` in a comment so that editing `.macos` changes the rendered script and retriggers it. Keep that hash line, and keep it on its own line — a `{{- ... -}}` trim there once swallowed the following statement into the comment. The script ends by restarting Dock/Finder/SystemUIServer/ControlCenter, so an apply visibly restarts UI elements.

Sudo-requiring system settings live separately in `run_onchange_darwin-security.sh.tmpl` (TouchID for sudo, application firewall, a FileVault *warning* that never aborts). They are kept out of `.macos` so that script can keep running unprivileged. These were previously inherited from strap.

`run_once_darwin-link-ssh.sh.tmpl` symlinks `~/.ssh` to iCloud Drive on personal machines only, and refuses to create a dangling link if iCloud has not synced.

## Shell

fish is the login shell; `run_onchange_setup-shell.sh.tmpl` registers it in `/etc/shells` and runs `chsh` (needs sudo). It is OS-agnostic — it resolves fish via `command -v`, not `homebrew_prefix`. Interactive config lives in `dot_config/private_fish/config.fish.tmpl` (abbreviations, `brew shellenv`, direnv/mise/cargo hooks); `conf.d/*.fish` files are auto-sourced and are the place for topic-scoped additions such as `wol.fish`.

**Do not generate completions into `~/.config/fish/completions/`.** That directory sorts first on `$fish_complete_path`, so anything written there shadows the current, package-manager-supplied completions in `$HOMEBREW_PREFIX/share/fish/vendor_completions.d/` — Homebrew already ships fish completions for docker, uv, uvx, bat, gh, rg, delta, chezmoi and more. An earlier version of this repo did exactly that and served nine-month-old copies as a result; `.chezmoiremove` now deletes those three files on every machine. The `generate_completions` function is an on-demand Linux fallback only: it writes to `~/.local/share/fish/vendor_completions.d/` and skips any command that already has a packaged completion.

Note that fisher installs into `~/.config/fish/{functions,completions,conf.d}` alongside chezmoi's managed files. chezmoi leaves unmanaged files alone, so the two coexist, but `chezmoi unmanaged ~/.config/fish` is worth checking before adding anything there.

## Linux

Supported for shell and CLI config only: fish, tmux, git, and fisher plugins. There is deliberately no Linux package management. `.chezmoiignore.tmpl` excludes the macOS-only targets (`~/.Brewfile`, `~/.config/zed`, `~/Library`, `.macos`, `.mutagen.yml`) on non-darwin. Keep new GUI app configs out of Linux by adding them to that block.

## CI

`.github/workflows/ci.yml` runs `chezmoi apply --dry-run` on `macos-latest` and `ubuntu-latest` across both `is_work` values, using `chezmoi init --promptString/--promptBool` to answer the prompts non-interactively. It also parses the generated Brewfile and shellchecks the rendered `.chezmoiscripts/`. Templates guarded on a non-matching OS render empty and are skipped by the lint step — if you add a script, make sure its OS guard wraps the *whole* file so this holds.

## Conventions

Commit messages are short, lowercase, imperative (`add wol gpu abbrs`, `switch to ty lsp`).

`.chezmoiversion` pins a minimum chezmoi of 2.60.0.
