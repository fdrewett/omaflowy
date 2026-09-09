#!/bin/bash
# Push the working tree into the live plugin dir and reload.
#
# The installed plugin is a git clone, so the ordinary route (commit here,
# `omarchy plugin update`) needs a commit per iteration. This copies instead.
# Symlinking the repo in would be the obvious shortcut and is refused by the
# validator: a symlink inside a plugin folder could point loaded code at
# anything on disk once it lands in the trusted directory.
#
# `rescanPlugins` alone is not enough. The bar mounts one widget instance per
# monitor and only one of them owns the plugin's IPC target; a rescan left the
# owning instance running the previous code, so IPC calls hit the old version
# while the visible pill ran the new one. That looked exactly like a bug in the
# new code. Restart the shell unless --soft is asked for.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ID=$(jq -r .id "$HERE/manifest.json")
DEST="$HOME/.config/omarchy/plugins/$ID"
mkdir -p "$DEST"
rsync -a --delete --exclude .git --exclude __pycache__ "$HERE/" "$DEST/"
omarchy plugin validate "$DEST"
if [[ ${1:-} == --soft ]]; then
  omarchy-shell shell rescanPlugins
  echo "synced -> $DEST (soft reload; IPC may still answer from the old instance)"
else
  omarchy-restart-shell
  echo "synced -> $DEST (shell restarted)"
fi
