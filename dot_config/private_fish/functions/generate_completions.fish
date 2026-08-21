# Fallback completion generation for tools whose package manager does not ship
# fish completions.
#
# On macOS this should almost never be needed: Homebrew installs completions
# into $HOMEBREW_PREFIX/share/fish/vendor_completions.d, which fish reads
# automatically. Output goes to the XDG vendor directory rather than
# ~/.config/fish/completions, because the latter sorts first on
# $fish_complete_path and would shadow packaged completions with stale copies.

function __completion_is_packaged --argument-names cmd
    set -l own $HOME/.local/share/fish/vendor_completions.d
    for path in $fish_complete_path
        test $path = $own; and continue
        if test -f $path/$cmd.fish
            return 0
        end
    end
    return 1
end

function generate_completions --description 'Generate fish completions for tools lacking packaged ones'
    set -l dir $HOME/.local/share/fish/vendor_completions.d
    mkdir -p $dir

    for cmd in uv uvx
        if type -q $cmd; and not __completion_is_packaged $cmd
            echo "generating $cmd completions"
            $cmd --generate-shell-completion fish >$dir/$cmd.fish
        end
    end

    if type -q docker; and not __completion_is_packaged docker
        echo "generating docker completions"
        docker completion fish >$dir/docker.fish
    end
end
