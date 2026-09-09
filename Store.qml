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
  property string label: ""
  property bool loading: false
  property bool stale: false
  property string error: ""
  property double fetchedAt: 0

  // Ids completed locally but not yet absent from a fetch. The `all` source is
  // served from an export capped at one request per minute, so a refresh right
  // after a click can legitimately return the row still open. Without this the
  // item would reappear under the cursor and invite a second click.
  property var completedIds: ({})

  readonly property var visibleItems: {
    var out = []
    for (var i = 0; i < items.length; i++)
      if (!completedIds[items[i].id]) out.push(items[i])
    return out
  }
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

  function isCompleted(id) { return completedIds[id] === true }

  function complete(id) {
    if (!id || isCompleted(id)) return
    var next = {}
    for (var k in completedIds) next[k] = completedIds[k]
    next[id] = true
    completedIds = next               // drop the row now, reconcile on the next fetch
    writeProc.command = [helper, "complete", id]
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
        root.stale = data.stale === true
        root.fetchedAt = data.fetchedAt || 0

        // Forget only the local completions this fetch confirms. An id still
        // present is either a write that failed or an export too old to show
        // it yet; either way it stays hidden until a fetch proves otherwise.
        var present = {}
        for (var i = 0; i < root.items.length; i++) present[root.items[i].id] = true
        var kept = {}
        for (var id in root.completedIds) if (present[id]) kept[id] = true
        root.completedIds = kept
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
          // Put the optimistic removal back: a failed complete must not look
          // like a successful one.
          root.completedIds = ({})
          root.writeFailed(data && data.error ? data.error : "write failed")
        }
        root.refresh()
      }
    }
  }
}
