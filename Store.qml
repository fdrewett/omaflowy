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

  // --- auth --------------------------------------------------------------
  property bool authConfigured: false
  property bool authOwn: false
  property string authSource: ""
  property string authSourceKind: ""
  property bool authKeyring: false
  property string authHint: ""
  property string authError: ""
  property bool authSaving: false
  property bool authLoaded: false

  function loadAuth() {
    authProc.command = [helper, "auth", "status"]
    authProc.running = true
  }

  function clearToken() {
    if (authSaving) return
    authSaving = true
    authError = ""
    authProc.command = [helper, "auth", "clear"]
    authProc.running = true
  }

  // The token goes over STDIN, never argv -- an argument is visible to every
  // other user on the machine through `ps`. Same pattern omarchy.network uses
  // for wifi passwords.
  function setToken(value) {
    var t = String(value || "").trim()
    if (t === "" || authSaving) return
    authSaving = true
    authError = ""
    tokenProc.secret = t
    tokenProc.stdinEnabled = true    // re-open; the previous save closed it
    tokenProc.command = [helper, "auth", "set"]
    tokenProc.running = true
    authTimeout.restart()
  }

  // Nothing should leave the button reading "Checking..." forever. Verifying a
  // token is one HTTPS round trip plus a keyring write; 25s is generous.
  Timer {
    id: authTimeout
    interval: 25000
    onTriggered: {
      if (!root.authSaving) return
      tokenProc.running = false
      root.authSaving = false
      root.authError = "Timed out saving the token - is a keyring running?"
    }
  }

  // --- keybindings -------------------------------------------------------
  // Entirely local: reads and writes ~/.config/omaflowy/binds.lua and asks
  // Hyprland to reload. No network, and nothing here touches Workflowy.
  property var binds: ({})
  property var bindLabels: ({})
  property var bindOrder: []
  property var bindConflicts: ({})
  property bool bindsLoaded: false
  property bool bindsSaving: false
  property string bindsError: ""

  function loadBinds() {
    bindsProc.command = [helper, "binds", "read"]
    bindsProc.running = true
  }

  function saveBinds(payload) {
    if (bindsSaving) return
    bindsSaving = true
    bindsError = ""
    bindsProc.command = [helper, "binds", "write", JSON.stringify(payload)]
    bindsProc.running = true
  }

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
    id: authProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.authSaving = false
        var d = null
        try { d = JSON.parse(text) } catch (e) { d = null }
        if (!d || d.ok !== true) {
          root.authError = d && d.error ? d.error : "could not read the token setting"
          return
        }
        root.authError = ""
        if ("configured" in d) {
          root.authConfigured = d.configured === true
          root.authOwn = d.own === true
          root.authSource = d.source || ""
          root.authSourceKind = d.sourceKind || ""
          root.authKeyring = d.keyring === true
          root.authHint = d.hint || ""
          root.authLoaded = true
        } else {
          root.loadAuth()          // a clear/set reply: re-read the real state
          root.refresh()
        }
      }
    }
    onExited: function(code, status) { root.authSaving = false }
  }

  Process {
    id: tokenProc
    property string secret: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""                  // do not keep it in a QML property
      // Close the pipe as well as writing a newline. A reader that waits for
      // EOF rather than for a line would otherwise hang, and it cannot tell
      // "no more input yet" from "that is all there is".
      stdinEnabled = false
    }
    stdout: StdioCollector {
      onStreamFinished: {
        root.authSaving = false
        var d = null
        try { d = JSON.parse(text) } catch (e) { d = null }
        if (!d || d.ok !== true) {
          root.authError = d && d.error ? d.error : "could not save the token"
          return
        }
        root.authError = ""
        root.loadAuth()
        root.refresh()
      }
    }
    onExited: function(code, status) { root.authSaving = false }
  }

  Process {
    id: bindsProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.bindsSaving = false
        var d = null
        try { d = JSON.parse(text) } catch (e) { d = null }
        if (!d || d.ok !== true) {
          root.bindsError = d && d.error ? d.error : "could not read keybindings"
          return
        }
        root.bindsError = ""
        root.binds = d.binds || ({})
        if (d.labels) root.bindLabels = d.labels
        if (d.order) root.bindOrder = d.order
        root.bindConflicts = d.conflicts || ({})
        root.bindsLoaded = true
      }
    }
    onExited: function(code, status) { root.bindsSaving = false }
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
