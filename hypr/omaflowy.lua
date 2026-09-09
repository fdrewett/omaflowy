-- Omaflowy (Omarchy shell plugin). Source this from ~/.config/hypr/bindings.lua:
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/frank.omaflowy/hypr/omaflowy.lua")
--
-- Nothing loads a plugin's hypr/*.lua automatically -- the shell reads
-- manifest.json and the QML, and never touches Hyprland config. The line above
-- is the whole wiring.

-- Capture. The one worth a global bind: the path from "I just thought of
-- something" to a todo under today's date without leaving the window you are
-- in. Opens the panel with the cursor already in the field.
o.bind("SUPER + ALT + W", "Workflowy: capture a todo", "omarchy-shell omaflowy capture")

-- Today's list, without the field grabbing focus.
o.bind("SUPER + SHIFT + W", "Workflowy: today's todos", "omarchy-shell omaflowy toggle")

-- Straight to a tab. `tab` opens the panel and selects it: today | inbox | all.
o.bind("SUPER + ALT + I", "Workflowy: inbox", "omarchy-shell omaflowy tab inbox")
