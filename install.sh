#!/usr/bin/env bash
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
plugin_dir="$HOME/.config/omarchy/plugins/devnull.log"

for dependency in omarchy omarchy-shell python3 curl ssh-keygen xdg-mime; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$dependency" >&2
    exit 1
  fi
done

install -d -m 755 "$plugin_dir"
install -m 644 "$source_dir/manifest.json" "$source_dir/BarWidget.qml" "$source_dir/Model.js" "$plugin_dir/"
install -m 755 "$source_dir/devnull.py" "$plugin_dir/devnull.py"
omarchy plugin validate "$plugin_dir"

if omarchy-shell shell ping >/dev/null 2>&1; then
  omarchy plugin enable devnull.log
  echo "Open the dev/null widget in the bar and choose Connect your dev/null account."
else
  echo "Installed. Start Omarchy, then run: omarchy plugin enable devnull.log"
fi
