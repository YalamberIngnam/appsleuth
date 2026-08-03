#!/bin/sh

set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if [ -n "${PREFIX:-}" ]; then
    install_prefix=$PREFIX
elif [ -d /opt/homebrew/bin ] && [ -w /opt/homebrew/bin ]; then
    install_prefix=/opt/homebrew
elif [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
    install_prefix=/usr/local
else
    install_prefix="$HOME/.local"
fi

destination="$install_prefix/bin"

echo "Building AppSleuth in release mode…"
swift build --package-path "$project_root" -c release

mkdir -p "$destination"
install -m 0755 "$project_root/.build/release/appsleuth" "$destination/appsleuth"

echo "Installed AppSleuth at $destination/appsleuth"

legacy_command="$destination/aps"
if [ -L "$legacy_command" ] && [ "$(readlink "$legacy_command")" = "appsleuth" ]; then
    rm -f "$legacy_command"
    echo "Removed retired command alias at $legacy_command"
fi

short_command="$destination/appsl"
if [ -L "$short_command" ] && [ "$(readlink "$short_command")" = "appsleuth" ]; then
    echo "Short command already available at $short_command"
elif [ -e "$short_command" ] || [ -L "$short_command" ]; then
    echo "Warning: $short_command already exists, so the optional 'appsl' command was not installed."
else
    ln -s appsleuth "$short_command"
    echo "Installed short command at $short_command -> appsleuth"
fi

case ":$PATH:" in
    *":$destination:"*)
        echo "Run: appsleuth (or: appsl)"
        ;;
    *)
        echo
        echo "Add AppSleuth to your PATH by putting this line in ~/.zprofile:"
        echo "  export PATH=\"$destination:\$PATH\""
        echo "Then open a new Terminal window and run: appsleuth (or: appsl)"
        ;;
esac
