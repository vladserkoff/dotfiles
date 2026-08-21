# Dotfiles

macOS and Linux machine configuration, managed with [chezmoi](https://www.chezmoi.io/).

Primary target is macOS — personal and work machines, which differ by the
`is_work` flag answered at `chezmoi init`. Linux machines are supported for
shell and CLI configuration only (fish, tmux, git, fisher plugins); package
installation and GUI app configs are macOS-only.

## Bootstrapping a fresh Mac

Sign in to the App Store first (needed for `mas`), then:

```shell
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/vladserkoff/dotfiles/HEAD/scripts/setup)"
```

Run it from an interactive terminal. chezmoi reads its init prompts (`E-mail`,
`Is it a work machine?`) from `/dev/tty`, so with no controlling terminal it
fails partway through — after Homebrew is already installed. The script checks
for a terminal up front and tells you how to preseed the answers instead.

`curl ... | bash` works too, since `/dev/tty` is independent of stdin, but the
form above keeps stdin a tty as well, which stops Homebrew's installer from
silently dropping into `NONINTERACTIVE` mode.

`scripts/setup` installs only the prerequisites chezmoi cannot install itself —
Xcode Command Line Tools, Homebrew, and chezmoi — then hands off to
`chezmoi init --apply`. Everything else (packages, dotfiles, macOS defaults,
TouchID for sudo, firewall) is applied by chezmoi, so it is versioned here
rather than hidden in the bootstrap.

To freeze the Homebrew installer at a known commit instead of tracking its
`HEAD`, set `HOMEBREW_INSTALL_REF` to a SHA before running.

## Existing machines

```shell
chezmoi update              # git pull + apply          (abbr: chu)
chezmoi diff                # preview pending changes
BUNDLE_CLEANUP=1 chezmoi apply   # also uninstall anything not in packages.yaml
```

## Adding or removing software

Edit `.chezmoidata/packages.yaml` only. `~/.Brewfile` is generated from it by
chezmoi, so package changes show up as a real diff in `chezmoi diff`.

Entries are tiered: `universal` goes everywhere, `personal` applies when
`is_work` is false, `work` when it is true. `fisher` plugins sit at the top
level and install on every OS.

Formulae from non-official taps also need the tap listed under `taps` in the
same tier — Homebrew silently ignores formulae from taps that are not
explicitly trusted, so an undeclared tap means the package quietly never
installs.

## Layout

| Path | Purpose |
| --- | --- |
| `.chezmoidata/packages.yaml` | the only place packages are declared |
| `.chezmoitemplates/Brewfile` | shared Brewfile body, rendered into `~/.Brewfile` |
| `.chezmoiscripts/` | provisioning steps run during `apply` |
| `.macos` | `defaults write` settings, invoked by a chezmoi script |
| `scripts/setup` | fresh-machine bootstrap; never applied to `$HOME` |

## CI

`.github/workflows/ci.yml` renders every template across all
OS × `is_work` permutations, runs `chezmoi apply --dry-run` on both
`macos-latest` and `ubuntu-latest`, checks the generated Brewfile parses, and
shellchecks the rendered provisioning scripts.
