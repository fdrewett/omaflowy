# Omaflowy

Today's open Workflowy todos, in the Omarchy bar. Click one to complete it,
type to capture a new one, and hit a key from anywhere to add without leaving
the window you are in.

```
󰃭 3          ┌ Workflowy ──────────────────────┐
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
omarchy plugin add https://github.com/<you>/omaflowy.git --enable --yes
```

It authenticates as the `wf` CLI does, reading the token at runtime from
`~/.workflowy/config.json` (`accounts.<name>.token`). Nothing is stored in this
repo or in `shell.json`. If you have never used `wf`, create that file with a
[Workflowy API token](https://workflowy.com/api-key/):

```json
{ "activeAccount": "default", "accounts": { "default": { "token": "…" } } }
```

## Global keybinding

Nothing loads a plugin's Hyprland config automatically. Add one line to
`~/.config/hypr/bindings.lua`:

```lua
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/frank.omaflowy/hypr/omaflowy.lua")
```

That gives you `SUPER + ALT + W` (capture, cursor in the field),
`SUPER + ALT + T` (today's list) and `SUPER + ALT + I` (Inbox). Edit
[`hypr/omaflowy.lua`](hypr/omaflowy.lua) to pick your own.

> Check before you rebind. Hyprland accepts a second bind on a key already in
> use and the later one **silently wins** — `SUPER + SHIFT + W` was the first
> choice here and would have quietly taken over Omawrite.
>
> ```bash
> hyprctl binds -j | jq -r '.[] | "\(.modmask) \(.key)  \(.description)"' | sort
> ```
>
> Modmasks: SUPER 64, ALT 8, CTRL 4, SHIFT 1.

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

Inbox and All rows carry a move button. It files the node under today's day node
**and sets `layoutMode` to `todo`**.

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
omarchy-shell omaflowy tab inbox # open the panel on a tab (today|inbox|all)
```

`dev.sh` restarts the shell by default, and that is deliberate.
`rescanPlugins` alone left the widget instance that owns the plugin's IPC target
running the *previous* code, so IPC answered from the old version while the
visible pill ran the new one — which looks exactly like a bug in the new code.

Symlinking the repo into the plugins directory is refused by the validator: a
symlink inside a plugin folder could point loaded code at anything on disk once
it lands in the trusted directory. Hence the copy.

## Publishing

The id is `frank.omaflowy`. Change it in `manifest.json` to your own namespace
(`io.github.<you>.omaflowy`) before publishing, and update the `dofile` path in
the keybinding instructions to match — the plugin directory is named after the id.

## Licence

MIT.
