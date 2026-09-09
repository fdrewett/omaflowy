import QtQuick
import Quickshell.Io

// Everything that talks to Workflowy. The panel reads `items` and calls
// refresh/complete/add; it never sees a URL, a token, or an HTML name.
//
// The work happens in helper/omaflowy rather than here because reading a
// source means walking a subtree or filtering a whole-account export, and
// doing either by chaining Process/curl calls in QML would mean reimplementing
// the request pool, the HTML-to-text pass, and the classification rules in
// JavaScript. One process in, one JSON blob out.
Item {
  id: root
  visible: false

  // "today" | "inbox" | "all"
  property string source: "today"
  property int maxAge: 90
  property string exclude: ""

  property var items: []
  // Items dated today that live elsewhere in the tree -- Workflowy's own
  // "Found Dates". Only ever populated for the "today" source.
  property var found: []
  property string label: ""
  property bool loading: false
  property bool stale: false
  property string error: ""
  property double fetchedAt: 0

  // Ids acted on locally but not yet absent from a fetch. Reads are served
  // from an export capped at one request per minute, so a refresh right after
  // a click can legitimately return the row unchanged. Without this the item
  // would reappear under the cursor and invite a second click.
  property var hiddenIds: ({})

  function _visible(list) {
    var out = []
    for (var i = 0; i < list.length; i++)
      if (!hiddenIds[list[i].id]) out.push(list[i])
    return out
  }

  readonly property var visibleItems: _visible(items)
  readonly property var visibleFound: _visible(found)
  readonly property int count: visibleItems.length
  readonly property bool everLoaded: fetchedAt > 0

  readonly property string helper:
    Qt.resolvedUrl("helper/omaflowy").toString().replace(/^file:\/\//, "")

  signal writeFailed(string message)

  function refresh() {
    if (loading) return
    loading = true
    var argv = [helper, "list", source, "--max-age", String(maxAge)]
    if (exclude !== "") argv.push("--exclude", exclude)
    fetchProc.command = argv
    fetchProc.running = true
  }

  function isHidden(id) { return hiddenIds[id] === true }

  function _hide(id) {
    var next = {}
    for (var k in hiddenIds) next[k] = hiddenIds[k]
    next[id] = true
    hiddenIds = next                  // drop the row now, reconcile on the next fetch
  }

  function complete(id) {
    if (!id || isHidden(id)) return
    _hide(id)
    writeProc.command = [helper, "complete", id]
    writeProc.running = true
  }

  // Files the node under today's day node AND makes it a todo. Moving alone
  // would drop an Inbox bullet into today and then hide it, because the Today
  // tab only lists todo-formatted items.
  function moveToToday(id) {
    if (!id || isHidden(id)) return
    _hide(id)
    writeProc.command = [helper, "move", id]
    writeProc.running = true
  }

  function add(text, target) {
    var t = String(text || "").trim()
    if (t === "") return
    writeProc.command = [helper, "add", t, "--target",
                         target === "inbox" ? "inbox" : "today"]
    writeProc.running = true
  }

  Process {
    id: fetchProc
    // The helper prints one JSON object, so collect it and parse once rather
    // than driving a SplitParser per line.
    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false
        var data = null
        try { data = JSON.parse(text) } catch (e) {
          root.error = "helper returned unparseable output"
          return
        }
        if (!data.ok) { root.error = data.error || "unknown error"; return }
        root.error = ""
        root.label = data.label || ""
        root.items = data.items || []
        root.found = data.found || []
        root.stale = data.stale === true
        root.fetchedAt = data.fetchedAt || 0

        // Forget only the local edits this fetch confirms. An id still present
        // is either a write that failed or an export too old to have noticed;
        // either way it stays hidden until a fetch proves otherwise.
        var present = {}
        for (var i = 0; i < root.items.length; i++) present[root.items[i].id] = true
        for (var j = 0; j < root.found.length; j++) present[root.found[j].id] = true
        var kept = {}
        for (var id in root.hiddenIds) if (present[id]) kept[id] = true
        root.hiddenIds = kept
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.error = text.trim().split("\n").pop()
    }
    onExited: function(code, status) {
      root.loading = false
      if (code !== 0 && root.error === "") root.error = "helper exited " + code
    }
  }

  Process {
    id: writeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data = null
        try { data = JSON.parse(text) } catch (e) { data = null }
        if (!data || data.ok !== true) {
          // Put the optimistic removal back: a failed write must not look like
          // a successful one.
          root.hiddenIds = ({})
          root.writeFailed(data && data.error ? data.error : "write failed")
        }
        root.refresh()
      }
    }
  }
}
