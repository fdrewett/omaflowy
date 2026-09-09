-- Omaflowy (Omarchy shell plugin) — global keybindings.
--
-- Nothing loads a plugin's hypr/*.lua automatically. The shell reads
-- manifest.json and the QML and never touches Hyprland config, so sourcing
-- this is opt-in and skipping it entirely is a supported way to have no global
-- keys at all.
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/<plugin-id>/hypr/omaflowy.lua")
--
-- The plugin's settings panel (the cog beside Refresh) writes
-- ~/.config/omaflowy/binds.lua and reloads Hyprland, so the keys can be changed
-- without editing any of this. To set them by hand instead, either edit that
-- file or set `omaflowy_binds` BEFORE the dofile line:
--
--   omaflowy_binds = {
--     capture = "SUPER + SHIFT + N",  -- a different key
--     today   = false,                -- disabled
--     -- inbox omitted -> keeps its default
--   }
--   dofile(...)
--
-- A key set to `false` is not bound. A key left out keeps the default below.
--
-- CHECK BEFORE YOU BIND. Hyprland accepts a second bind on a key already in
-- use and the later one silently wins -- nothing warns, and `hyprctl
-- configerrors` stays empty. The defaults here were moved off SUPER+SHIFT+W
-- for exactly that reason: it was already Omawrite, and sourcing this file
-- would have quietly taken it over.
--
--   hyprctl binds -j | jq -r '.[] | "\(.modmask) \(.key)  \(.description)"' | sort
--
-- Modmasks: SUPER 64, ALT 8, CTRL 4, SHIFT 1 -- so SUPER+ALT is 72. Note that
-- omarchy's own binds show as `dispatcher: __lua` with a numeric `arg` rather
-- than the command, so match on the description, not the command name.

local defaults = {
  -- Capture on whichever tab the panel was left on, cursor in the field. The
  -- one worth a global key: from "I just thought of something" to a todo under
  -- today's date without leaving the window you are in.
  capture = "SUPER + ALT + W",
  -- Same landing, pinned to Today. Pressing either again while the cursor is
  -- in the field dismisses the panel.
  today   = "SUPER + ALT + T",
  -- Inbox, focus left on the panel: triage rather than capture. Use
  -- `omarchy-shell omaflowy captureIn inbox` instead to land in the field.
  inbox   = "SUPER + ALT + I",
}

local actions = {
  capture = { "Workflowy: capture a todo",  "omarchy-shell omaflowy capture" },
  today   = { "Workflowy: today's todos",   "omarchy-shell omaflowy captureIn today" },
  inbox   = { "Workflowy: inbox",           "omarchy-shell omaflowy tab inbox" },
}

-- Precedence, least to most specific:
--   defaults  <  omaflowy_binds set here  <  ~/.config/omaflowy/binds.lua
--
-- The file is last because it is what the plugin's own settings panel writes,
-- and a cog that appears to do nothing because a hand-edited global outranks it
-- would be worse than no cog. Delete the file to fall back to whatever this
-- config says. It is loaded with loadfile + pcall so a corrupt or half-written
-- file costs the binds, not the whole Hyprland config.
local cfg = {}
for k, v in pairs(omaflowy_binds or {}) do cfg[k] = v end

local chunk = loadfile(os.getenv("HOME") .. "/.config/omaflowy/binds.lua")
if chunk then
  local ok, t = pcall(chunk)
  if ok and type(t) == "table" then
    for k, v in pairs(t) do cfg[k] = v end
  end
end

for name, action in pairs(actions) do
  -- nil means "not configured" and takes the default; false means "off".
  -- They are distinct, which is why this is not `cfg[name] or defaults[name]`.
  local key = cfg[name]
  if key == nil then key = defaults[name] end
  if key then o.bind(key, action[1], action[2]) end
end
