# Omaflowy

Today's open Workflowy todos, in the Omarchy bar. Click one to complete it,
type to capture a new one, and hit a key from anywhere to add without leaving
the window you are in.

```
○ 3          ┌ Workflowy ──────────────────────┐
             │ 3 items              2026-09-08 │
             │ ┌───────────────────────┐ ┌───┐ │
             │ │ New todo for today…   │ │Add│ │
             │ └───────────────────────┘ └───┘ │
             │ [ Today ] Inbox   All           │
             │ ─────────────────────────────── │
             │ ○ schedule the on-call meeting  │
             │   Tuesday plan — 8 Sep / This…  │
             │ ○ start the team check-ins      │
             │   Tuesday plan — 8 Sep / This…  │
             └─────────────────────────────────┘
```

## Install

```bash
omarchy plugin add https://github.com/fdrewett/omaflowy.git --enable --yes
```

## How it authenticates

A **Workflowy personal API token** — no OAuth, no account linking, no server in
the middle. Get one at <https://workflowy.com/api-key/>.

Two ways to provide it, checked in this order:

1. **The settings panel** — the cog beside Refresh has a token field. It
   verifies the token against Workflowy before saving it to
   `~/.config/omaflowy/token`, created `0600`. Nothing else to install.
2. **The [`wf` CLI](https://github.com/malcolmocean/workflowy-cli)'s config** at
   `~/.workflowy/config.json`, used as a fallback so an existing `wf` setup
   needs no configuration at all:

   ```json
   { "activeAccount": "default", "accounts": { "default": { "token": "…" } } }
   ```

The panel's own file wins when both exist: someone who has just typed a token
into the panel means that one.

Nothing is stored in this repo or in `shell.json`. Specifically:

- The token is used **only** as an `Authorization: Bearer` header to
  `workflowy.com`. That is the sole outbound host — there is no telemetry and
  no third party.
- It is **never passed as a command-line argument**, so it does not appear in
  `ps` output to other users on the machine. That holds when saving it too: the
  settings panel writes it to the helper's **stdin**, the same way
  `omarchy.network` hands over a wifi password. The QML side otherwise never
  sees it; it hands the helper node ids and text, and the helper adds the
  header.
- It is never logged. The `debug` IPC method reports counts and panel state
  only, never content or credentials.

**What does land on disk:** `~/.cache/omaflowy/export.json`, a copy of your
whole Workflowy account (~19k nodes / ~6MB in one real account) used to serve
all three tabs from a single request. The token is *not* in it, but the content
is everything you have ever written, so the plugin creates the directory `0700`
and the file `0600` — owner-only. Delete it any time; it is rebuilt on the next
refresh.

Read [`helper/omaflowy`](helper/omaflowy) if you would rather check than take
this on trust. It is standard-library Python with no dependencies, and it is
the only file that talks to the network.

> Plugins run **unsandboxed with your user permissions** in the shared Omarchy
> shell process. That is true of every plugin, this one included — read the
> source before installing it.

## Global keybindings

Optional, and opt-in: nothing loads a plugin's Hyprland config automatically,
so **skipping this leaves the plugin with no global keys at all.** To enable
them, add one line to `~/.config/hypr/bindings.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.fdrewett.omaflowy/hypr/omaflowy.lua")
```

| Default | Does |
|---|---|
| `SUPER + ALT + W` | open on the current tab, cursor in the field |
| `SUPER + ALT + T` | open on **Today**, cursor in the field |
| `SUPER + ALT + I` | open on **Inbox**, focus left on the panel |

The two capture binds toggle: pressing again while the cursor is in the field
dismisses the panel.

### Changing or disabling them

**From the panel:** the cog beside Refresh opens a keyboard-shortcut editor —
a toggle to switch each bind off and a field to retype the combo. Saving writes
`~/.config/omaflowy/binds.lua` and reloads Hyprland. It warns when a combo is
already held by another bind, which is otherwise invisible.

**By hand:** set `omaflowy_binds` **before** the `dofile`. A string rebinds,
`false` disables, and anything left out keeps its default:

```lua
omaflowy_binds = {
  capture = "SUPER + SHIFT + N",  -- rebind
  today   = false,                -- off
  -- inbox omitted -> keeps SUPER + ALT + I
}
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/io.github.fdrewett.omaflowy/hypr/omaflowy.lua")
```

> **Check before you bind.** Hyprland accepts a second bind on a key already in
> use and the later one **silently wins** — nothing warns, and `hyprctl
> configerrors` stays empty. The defaults were moved off `SUPER + SHIFT + W`
> for exactly that reason: it was already Omawrite, and sourcing this file
> would have quietly taken it over.
>
> ```bash
> hyprctl binds -j | jq -r '.[] | "\(.modmask) \(.key)  \(.description)"' | sort
> ```
>
> Modmasks: SUPER 64, ALT 8, CTRL 4, SHIFT 1. Omarchy's own binds show as
> `dispatcher: __lua` with a numeric `arg` rather than the command, so match on
> the description.

Precedence is defaults < `omaflowy_binds` < `~/.config/omaflowy/binds.lua`. The
file wins because it is what the settings panel writes, and a cog that appeared
to do nothing because a hand-edited global outranked it would be worse than no
cog. Delete the file to fall back to whatever `bindings.lua` says.

## The three tabs

| Tab | Shows | Rule |
|---|---|---|
| **Today** | open todos under today's calendar day node, then **Found Dates** | `layoutMode == "todo"`, not completed |
| **Inbox** | everything open in the Inbox | any layout, not completed |
| **All** | every open todo in the account | `layoutMode == "todo"`, not completed |

Today and All are strict about todo formatting because a day node is also where
narrative gets written — "dinner with the folks" is a bullet, not a task — and a
recurring template can stamp a dozen empty section headers into a day, every one
of them technically an open bullet.

The Inbox is the opposite. Nothing there is todo-formatted, because putting
something in the Inbox *is* the claim that it needs doing. Applying the day rule
to it returns an empty list, always.

Capture follows the tab you are looking at: typing in the Inbox view files to
the Inbox, everywhere else it files under today. Either way the text is sent as
`- [ ] …`, the markdown marker that makes Workflowy store it as a real todo, so
what you add comes back as something these tabs can see.

A completed *ancestor* does not hide an open todo. Ticking off a section header
like "Tuesday plan — 8 Sep" leaves the unticked todos under it visible, which is
what Workflowy itself does.

### Found Dates

Below today's list, the same thing Workflowy calls Found Dates: open items
carrying a date pill for today that live somewhere else entirely. A line written
under last Friday saying "chase the gate permit `[today]`" is work due
today and is nowhere near today's bullets.

Matching is on the `<time>` element's `startYear`/`startMonth`/`startDay`
attributes, not its rendered label, which is Workflowy's to format. Two things
are excluded, both of which the app excludes too and both of which turned up on
the first run: the day node itself is named with its own date and matches
trivially, and anything already under the day node is in the list above. A time
of day, when the pill carries one, is shown on the line and sorts the section.

### Move to today

Inbox and All rows carry a move button, marked with Workflowy's own Today icon
(`󰃭`). It files the node under today's day node **and sets `layoutMode` to
`todo`**.

Both halves are needed. Moving alone would drop an Inbox bullet into today and
then hide it, because the Today tab only lists todo-formatted items — the thing
would vanish from both lists. Setting `layoutMode` on an existing node is
something only the public API can do; the MCP server ignores `block_format` on
replace.

## Settings

`omarchy bar` settings, or the `barWidget` entry in `~/.config/omarchy/shell.json`:

| Key | Default | What |
|---|---|---|
| `refreshSec` | 300 | refresh interval with the panel closed |
| `openRefreshSec` | 60 | refresh interval with the panel open |
| `exportMaxAgeSec` | 90 | how long a cached read stays usable |
| `excludePaths` | `""` | comma-separated subtree names to skip |
| `hideWhenEmpty` | false | hide the pill when today is clear |

`excludePaths` exists for recurring templates. If a daily check-in template
stamps a block of section headers into every day, name its parent here and they
stop competing with real work.

## Focus, and a race worth knowing about

`captureIn` selects a tab, opens the panel and puts the cursor in the capture
field. Focus is asserted on a short retry rather than once, because a single
`Qt.callLater` loses a race it cannot see: `KeyboardPanel` drives focus to its
own key catcher while the popup opens, and switching tabs adds a fetch and a
relayout on top. Firing once happened to work from the already-correct tab and
silently did nothing whenever the tab changed — the bind looked wired and did
half its job.

The retry deliberately gives up when the panel reads closed rather than
reopening it. Reopening was tried: an `open()` during the closing animation is
swallowed, so the retry reopens, the field takes focus off the key catcher, the
panel treats that as focus lost and closes, and the two chase each other until
the budget runs out. Losing a keypress issued mid-close is the smaller problem
and it fixes itself on the next press.

## Envelope keys

Three endpoints, three conventions, none of them documented — verified
2026-09-08:

```
GET  /nodes/:id  ->  {"node":  {...}}      singular
GET  /nodes      ->  {"nodes": [...]}      plural
POST /nodes      ->  {"item_id": "..."}    neither
```

## How it reads Workflowy

Everything goes through `helper/omaflowy`, a standard-library Python script.
The QML runs it and parses one JSON blob; the panel never sees a URL, a token,
or an HTML name.

All three tabs are served from a single `/nodes-export` call, cached on disk at
`~/.cache/omaflowy/export.json` and shared by every widget instance.

That is not the obvious design, and the obvious one does not work. Addressing
each source directly means walking a subtree, and there is no subtree endpoint —
one day measured 94 requests across four levels. The bar mounts one widget per
monitor, so a two-monitor refresh was ~376 requests every cycle and Workflowy
answered 429.

The way that failed is the reason the cache is not just an optimisation. The
first version treated every failed request as an empty node, so a rate-limited
walk returned `0 todos` with `ok: true` — confidently, on one monitor, while the
other showed 3. A todo list that hides work is worse than one that admits it is
broken, so now only a 404 means empty and everything else surfaces as an error
in the pill.

`/nodes-export` returns the whole account (~19k nodes, ~6MB) in about 0.7s,
faster than walking a single day was. It is limited to **one request per
minute**, so reads are locked with `flock` — otherwise both monitors race on a
cold cache and the loser is refused — and a stale cache is always served in
preference to a failed refresh. Total cost is at most two requests a minute
regardless of monitors, tabs, or refreshes.

Completing a row removes it locally straight away rather than waiting for a
re-read, because the next read may legitimately be a cache too young to have
noticed.

## Developing

```bash
./dev.sh          # sync into ~/.config/omarchy/plugins/ and restart the shell
./dev.sh --soft   # rescanPlugins instead of a restart
omarchy plugin validate .
omarchy-shell omaflowy debug     # store state: error, count, last fetch
omarchy-shell omaflowy tab inbox       # open on a tab (today|inbox|all)
omarchy-shell omaflowy captureIn today # open on a tab, cursor in the field
```

`dev.sh` restarts the shell by default, and that is deliberate.
`rescanPlugins` alone left the widget instance that owns the plugin's IPC target
running the *previous* code, so IPC answered from the old version while the
visible pill ran the new one — which looks exactly like a bug in the new code.

Symlinking the repo into the plugins directory is refused by the validator: a
symlink inside a plugin folder could point loaded code at anything on disk once
it lands in the trusted directory. Hence the copy.

## Publishing

The id is `io.github.fdrewett.omaflowy`, the reverse-domain convention the
marketplace expects. Forking to publish your own? Change it in `manifest.json`
to your namespace — the plugin directory is named after the id, so the `dofile`
path in the keybinding instructions follows it.

Submit via the marketplace's
[issue template](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml).

## Licence

MIT.
