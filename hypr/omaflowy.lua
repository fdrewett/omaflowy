-- Omaflowy (Omarchy shell plugin). Source this from ~/.config/hypr/bindings.lua:
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/frank.omaflowy/hypr/omaflowy.lua")
--
-- Nothing loads a plugin's hypr/*.lua automatically -- the shell reads
-- manifest.json and the QML, and never touches Hyprland config. The line above
-- is the whole wiring.
--
-- These are SUGGESTIONS, not reservations. Hyprland accepts a second bind on a
-- key already in use and the later one simply wins, silently: SUPER+SHIFT+W
-- was tried here first and would have quietly taken over Omawrite. Check
-- before adding your own:
--
--   hyprctl binds -j | jq -r '.[] | "\(.modmask) \(.key)  \(.description)"' | sort
--
-- Modmasks: SUPER 64, ALT 8, CTRL 4, SHIFT 1 (so SUPER+ALT is 72).

-- Capture. The one worth a global bind: the path from "I just thought of
-- something" to a todo under today's date without leaving the window you are
-- in. Opens the panel with the cursor already in the field.
o.bind("SUPER + ALT + W", "Workflowy: capture a todo", "omarchy-shell omaflowy capture")

-- Today, cursor in the field. Same landing as capture but pinned to Today.
-- Pressing it again while the cursor is in the field dismisses the panel.
o.bind("SUPER + ALT + T", "Workflowy: today's todos", "omarchy-shell omaflowy captureIn today")

-- Straight to the inbox, for triage rather than capture -- so `tab`, which
-- leaves focus on the panel. Swap to `captureIn inbox` to land in the field.
o.bind("SUPER + ALT + I", "Workflowy: inbox", "omarchy-shell omaflowy tab inbox")
