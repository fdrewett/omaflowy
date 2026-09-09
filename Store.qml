import QtQuick
import Quickshell.Io

// Everything that talks to Workflowy. The panel reads `todos` / `notes` and
// calls refresh/complete/add; it never sees a URL or a token.
//
// The work happens in helper/omaflowy rather than here because reading a day
// means walking a subtree, and there is no subtree endpoint — one measured day
// was 94 requests across four levels. Chaining that through Process/curl in
// QML would mean reimplementing the pool, the HTML-to-text pass, and the
// classification rules in JavaScript, and re-deriving them the next time the
// shape changes. One process in, one JSON blob out.
Item {
  id: root
  visible: false

  property int depth: 4
  property string exclude: ""

  property var todos: []
  property var notes: []
  property bool loading: false
  property string error: ""
  property string date: ""
  property double fetchedAt: 0

  // Set the moment a row is clicked, cleared when the refresh that follows
  // comes back. The API round-trip is ~300ms; without this the row sits there
  // looking untouched and invites a second click that completes nothing.
  property var pending: ({})

  readonly property int count: todos.length
  readonly property bool everLoaded: fetchedAt > 0

  readonly property string helper:
    Qt.resolvedUrl("helper/omaflowy").toString().replace(/^file:\/\//, "")

  signal loaded()

  function refresh() {
    if (loading) return
    loading = true
    var argv = [helper, "today", "--depth", String(depth)]
    if (exclude !== "") argv.push("--exclude", exclude)
    fetchProc.command = argv
    fetchProc.running = true
  }

  function isPending(id) { return pending[id] === true }

  function complete(id) {
    if (!id || isPending(id)) return
    var p = {}
    for (var k in pending) p[k] = pending[k]
    p[id] = true
    pending = p
    writeProc.command = [helper, "complete", id]
    writeProc.running = true
  }

  function add(text) {
    var t = String(text || "").trim()
    if (t === "") return
    writeProc.command = [helper, "add", t]
    writeProc.running = true
  }

  Process {
    id: fetchProc
    // The helper prints one JSON object on stdout, so collect the lot and
    // parse once rather than driving a SplitParser per line.
    stdout: StdioCollector {
      onStreamFinished: {
        root.loading = false
        var data = null
        try {
          data = JSON.parse(text)
        } catch (e) {
          root.error = "helper returned unparseable output"
          return
        }
        if (!data.ok) {
          root.error = data.error || "unknown error"
          return
        }
        root.error = ""
        root.date = data.date || ""
        root.todos = data.todos || []
        root.notes = data.notes || []
        root.fetchedAt = data.fetchedAt || 0
        // Anything still marked pending has now been read back as gone (or is
        // genuinely still open, in which case the write failed and it should
        // be clickable again). Either way the optimistic state is spent.
        root.pending = ({})
        root.loaded()
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") root.error = text.trim().split("\n").pop()
    }
    onExited: function(code, status) {
      root.loading = false
      // A non-zero exit with nothing on stdout means the helper died before it
      // could report; the JSON path above already handled the reported errors.
      if (code !== 0 && root.error === "") root.error = "helper exited " + code
    }
  }

  Process {
    id: writeProc
    stdout: StdioCollector {
      onStreamFinished: {
        var ok = false
        try { ok = JSON.parse(text).ok === true } catch (e) { ok = false }
        if (!ok) root.pending = ({})
        // Read back either way: on success to drop the row, on failure to
        // restore the truth rather than leave a half-applied local guess.
        root.refresh()
      }
    }
  }
}
