-- Omaflowy (Omarchy shell plugin). Source this from ~/.config/hypr/bindings.lua:
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/frank.omaflowy/hypr/omaflowy.lua")
--
-- Nothing loads a plugin's hypr/*.lua automatically -- the shell reads
-- manifest.json and the QML, and never touches Hyprland config. The line above
-- is the whole wiring.

-- Open the panel with the cursor already in the capture field. This is the one
-- worth a global bind: it is the path from "I just thought of something" to a
-- todo under today's date without leaving the window you are in.
o.bind("SUPER + ALT + W", "Workflowy: capture a todo", "omarchy-shell omaflowy capture")

-- The list, without the field grabbing focus.
o.bind("SUPER + SHIFT + W", "Workflowy: today's todos", "omarchy-shell omaflowy toggle")
