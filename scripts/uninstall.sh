#!/bin/sh

set -eu

if [ -n "${PREFIX:-}" ]; then
    install_prefix=$PREFIX
elif [ -x /opt/homebrew/bin/appsleuth ]; then
    install_prefix=/opt/homebrew
elif [ -x /usr/local/bin/appsleuth ]; then
    install_prefix=/usr/local
else
    install_prefix="$HOME/.local"
fi

binary="$install_prefix/bin/appsleuth"
short_command="$install_prefix/bin/appsl"
legacy_command="$install_prefix/bin/aps"

if [ ! -e "$binary" ] && [ ! -L "$short_command" ] && [ ! -L "$legacy_command" ]; then
    echo "AppSleuth is not installed at $binary"
    exit 0
fi

printf "Remove %s and its 'appsl' command alias? [y/N] " "$binary"
read -r answer
case "$answer" in
    y|Y|yes|YES)
        rm -f "$binary"
        echo "Removed $binary"
        if [ -L "$short_command" ] && [ "$(readlink "$short_command")" = "appsleuth" ]; then
            rm -f "$short_command"
            echo "Removed $short_command"
        fi
        if [ -L "$legacy_command" ] && [ "$(readlink "$legacy_command")" = "appsleuth" ]; then
            rm -f "$legacy_command"
            echo "Removed retired alias $legacy_command"
        fi
        echo "Restore vaults under ~/.local/share/appsleuth were left untouched."
        ;;
    *)
        echo "Cancelled."
        ;;
esac
