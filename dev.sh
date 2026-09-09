#!/bin/bash
# Push the working tree into the live plugin dir and reload the shell.
#
# The installed plugin is a git clone, so the ordinary route (commit here,
# `omarchy plugin update`) needs a commit per iteration. This copies instead.
# Symlinking the repo in would be the obvious shortcut and is refused by the
# validator: a symlink inside a plugin folder could point loaded code at
# anything on disk once it lands in the trusted directory.
set -euo pipefail
ID=$(jq -r .id "$(dirname "$0")/manifest.json")
DEST="$HOME/.config/omarchy/plugins/$ID"
mkdir -p "$DEST"
rsync -a --delete --exclude .git --exclude __pycache__ "$(dirname "$0")/" "$DEST/"
omarchy-shell shell rescanPlugins
echo "synced -> $DEST"
