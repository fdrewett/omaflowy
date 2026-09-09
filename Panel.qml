pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar pill + popup in one entry point, the shape omarchy.tailscale and
// omarchy.network use: the bar mounts this item, the pill is a child of it,
// and the popup hangs off the pill as its anchor.
Panel {
  id: root
  moduleName: "io.github.fdrewett.omaflowy"
  ipcTarget: "omaflowy"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Found dates only mean anything against a specific day, so they ride with
  // the Today tab and nowhere else.
  readonly property bool showFound:
    sources[sourceIndex] === "today" && store.visibleFound.length > 0
  // Somewhere else in the tree is exactly where these live, so the move is the
  // useful action; on the Today tab it would be a no-op.
  readonly property bool canMove: sources[sourceIndex] !== "today"

  readonly property var sources: ["today", "inbox", "all"]
  readonly property var sourceLabels: ["Today", "Inbox", "All"]
  property int sourceIndex: 0
  property bool settingsOpen: false
  property bool menuOpen: false

  function closeMenu() { menuOpen = false }

  function toggleSettings() {
    menuOpen = false
    settingsOpen = !settingsOpen
    if (settingsOpen && !store.bindsLoaded) store.loadBinds()
    if (settingsOpen && !store.authLoaded) store.loadAuth()
  }

  // The pill always counts today, whatever tab is showing. A bar number that
  // changed because you clicked a tab would not be a number you could trust
  // at a glance, which is the only thing a bar number is for.
  property int todayCount: 0
  property bool todayLoaded: false

  // Workflowy's own Today icon (and the glyph omarchy.clock uses for a date, so
  // it is native to the bar rather than borrowed). It means exactly one thing
  // in this panel -- "today" -- which is why the bar pill does not also use it:
  // two different meanings on one glyph and neither reads.
  readonly property string todayIcon: "󰃭"
  readonly property string pillText:
    store.error !== "" ? "󰅚" : (todayLoaded ? "󰄰 " + todayCount : "󰄰 ·")

  readonly property string heroMeta: {
    if (store.authLoaded && !store.authConfigured) return "No API token — open ⋮ → Settings"
    if (store.error !== "") return store.error
    if (!store.everLoaded) return "Loading…"
    var n = store.count
    var f = store.visibleFound.length
    var parts = []
    if (n > 0) parts.push(n + (n === 1 ? " item" : " items"))
    if (f > 0) parts.push(f + " dated today")
    if (parts.length === 0) parts.push("Nothing open")
    if (store.stale) parts.push("cached")
    return parts.join(" · ")
  }

  function refresh() { store.refresh(); todayProbe.reload() }

  Connections {
    target: store
    // Keep the pill in step without a second read when Today is on screen.
    function onItemsChanged() {
      if (root.sources[root.sourceIndex] !== "today") return
      root.todayCount = store.count
      root.todayLoaded = true
    }
  }

  function selectSource(i) {
    var next = Math.max(0, Math.min(i, sources.length - 1))
    if (next === sourceIndex) return
    sourceIndex = next
    store.refresh()
  }

  function openNode(id) {
    // Web URLs address a node by the last segment of its UUID -- the same
    // 12-character short id the MCP server uses.
    //
    // bar.run() hands this to a shell, so the id is validated rather than
    // trusted. Ids come from the API and are hex today, but "the server only
    // ever sends us safe values" is not a property this side can enforce, and
    // the cost of being wrong is arbitrary command execution.
    var short = String(id || "").slice(-12)
    if (!bar || !/^[0-9a-f]{12}$/.test(short)) return
    bar.run("xdg-open 'https://workflowy.com/#/" + short + "'")
  }

  function submitCapture() {
    if (capture.text.trim() === "") return
    // Capture follows the tab you are looking at: typing into the Inbox view
    // and having the line land on today's date would be a quiet misfile.
    store.add(capture.text, sources[sourceIndex] === "inbox" ? "inbox" : "today")
    capture.text = ""
  }

  // Opens the panel with the cursor already in the field, for the global
  // keybindings. Selecting the tab first means the placeholder, and the list
  // the text will be filed to, are already right when the cursor lands.
  //
  // Focus is asserted on a short retry rather than once, because a single
  // Qt.callLater loses a race it cannot see: KeyboardPanel drives focus to its
  // own key catcher while the popup is opening, and switching tabs adds a
  // fetch and a relayout on top. Firing once happened to work from the
  // already-correct tab and silently did nothing whenever the tab changed.
  function captureFocus(tabName) {
    var i = tabName ? root.sources.indexOf(String(tabName).toLowerCase()) : -1
    // Pressing the same bind again, already in the field, dismisses. Without
    // this the second press is a coin flip: re-asserting focus the field
    // already holds makes the panel treat it as focus lost and close anyway,
    // so the behaviour existed regardless -- this just makes it deliberate.
    if (root.opened && capture.activeFocus && (i < 0 || i === sourceIndex)) {
      root.close()
      return
    }
    if (i >= 0) root.selectSource(i)
    root.open()
    _focusTries = 0
    focusTimer.restart()
  }

  property int _focusTries: 0

  Timer {
    id: focusTimer
    interval: 60
    repeat: true
    onTriggered: {
      // Stop on success, on the panel being gone, or after ~0.8s.
      //
      // Do NOT reissue open() from in here when the panel reads closed. That
      // was tried: an open during the closing animation is swallowed, so the
      // retry reopens, the field grabs focus off the panel's key catcher, the
      // panel treats that as focus lost and closes, and the two chase each
      // other until the budget runs out. Losing a keypress issued mid-close is
      // the smaller problem, and it fixes itself on the next press.
      if (!root.opened || capture.activeFocus || ++root._focusTries > 13) {
        stop()
        return
      }
      capture.forceActiveFocus()
    }
  }

  Store {
    id: store
    source: root.sources[root.sourceIndex]
    maxAge: root.setting("exportMaxAgeSec", 90)
    exclude: root.setting("excludePaths", "")
    onWriteFailed: function(message) { root.refresh() }
  }

  // A second read of today that keeps the pill honest while another tab is
  // open. It costs no request of its own: every source is served from the same
  // cached export, so this only re-filters a file the store has already paid
  // for. When Today is the visible tab the store's own result is authoritative
  // and the probe stands down.
  Process {
    id: todayProbe
    command: [store.helper, "list", "today", "--max-age",
              String(root.setting("exportMaxAgeSec", 90))]
             .concat(root.setting("excludePaths", "") !== ""
                     ? ["--exclude", root.setting("excludePaths", "")] : [])
    function reload() {
      if (root.sources[root.sourceIndex] === "today") return
      if (!running) running = true
    }
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          if (d.ok) { root.todayCount = d.count; root.todayLoaded = true }
        } catch (e) { /* the pill keeps its last honest value */ }
      }
    }
  }

  Component.onCompleted: { root.refresh(); store.loadAuth() }

  Timer {
    // Two rates, the pattern harshith.system-monitor uses: a slow beat to keep
    // the pill honest, a faster one while someone is looking at the list.
    interval: 1000 * (root.opened ? root.setting("openRefreshSec", 60)
                                  : root.setting("refreshSec", 300))
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Connections {
    target: root
    // Opening should not show a stale list, but re-fetching on every toggle
    // would burn requests while the panel is flicked open and shut.
    function onOpenedChanged() {
      if (!root.opened) root.menuOpen = false
      if (root.opened && Date.now() / 1000 - store.fetchedAt > 30) root.refresh()
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return "ok" }
    function count(): string { return String(root.todayCount) }
    function debug(): string {
      return JSON.stringify({ err: store.error, loading: store.loading,
                              n: store.count, found: store.visibleFound.length,
                              at: store.fetchedAt, tab: root.sources[root.sourceIndex],
                              opened: root.opened, fieldFocus: capture.activeFocus,
                              probe: root.todayLoaded })
    }
    // The global keybinding's entry points.
    // Open + focus the field, on whichever tab is showing.
    function capture(): string { root.captureFocus(""); return "ok" }
    // Open + select a tab + focus the field. Separate from `tab` because
    // browsing and capturing are different intents: landing in the field means
    // the panel's single-key shortcuts are swallowed by the text box.
    function captureIn(name: string): string {
      if (root.sources.indexOf(String(name || "").toLowerCase()) < 0) return "unknown tab"
      root.captureFocus(name)
      return "ok"
    }
    // Open the keyboard-shortcut editor.
    function settings(): string {
      root.open()
      if (!root.settingsOpen) root.toggleSettings()
      return "ok"
    }
    // Open + select a tab, leaving focus on the panel.
    function tab(name: string): string {
      var i = root.sources.indexOf(String(name || "").toLowerCase())
      if (i < 0) return "unknown tab"
      root.open()
      root.selectSource(i)
      return "ok"
    }
    // Capture without opening anything, for a bind that should not steal focus.
    function add(text: string): string {
      if (!text || text.trim() === "") return "empty"
      store.add(text, "today")
      return "ok"
    }
  }

  visible: !(root.setting("hideWhenEmpty", false) && root.todayLoaded && root.todayCount === 0)
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pillText
    active: store.error !== ""
    tooltipText: store.error !== "" ? store.error : "Workflowy — today"

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.captureFocus()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(420))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The capture field wants every keystroke it can get, so the catcher
      // stands down while it has focus -- otherwise typing "r" in a todo would
      // fire the refresh shortcut instead of landing in the text.
      blocked: capture.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "n" || t === "N") capture.forceActiveFocus()
        else if (t === "1") root.selectSource(0)
        else if (t === "2") root.selectSource(1)
        else if (t === "3") root.selectSource(2)
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        // `policy: AsNeeded` does not make this non-interactive when there is
        // nothing to scroll -- measured as visible, opacity 1, interactive,
        // 10px wide, sitting over x 378..388 of a 388-wide panel with content
        // exactly as tall as the viewport. Anything flush with the right edge
        // therefore lost its last 10px to it: the ⋮ menu and the Add button
        // both looked like they had a broken hit box.
        ScrollBar.vertical: ScrollBar { id: vbar; policy: ScrollBar.AsNeeded }

        Column {
          id: column
          // Reserve the scrollbar's gutter instead of drawing underneath it.
          // Bound to vbar.width, which is a constant from the style -- binding
          // it to whether the bar is *needed* would loop, because that depends
          // on contentHeight, which depends on this width.
          width: flick.width - vbar.width
          spacing: Style.space(12)

          // The header is assembled here rather than handed to PanelHero's
          // `trailingControl`. That slot is a bare Loader with no explicit
          // size, so a Row placed in it paints wider than it measures and the
          // right-hand part of the last button stops taking clicks -- the ⋮
          // was dead along its right edge. Anchoring the actions directly
          // makes the hit area and the paint area the same rectangle.
          Item {
            id: header
            width: parent.width
            implicitHeight: Math.max(heroSlot.implicitHeight,
                                     headerActions.implicitHeight)

            Item {
              id: heroSlot
              anchors.left: parent.left
              anchors.right: headerActions.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              implicitHeight: hero.implicitHeight

              PanelHero {
                id: hero
                // `detail` is deliberately unset. PanelHero renders it as a
                // pill inside the label column, and that column is inset by
                // the trailing control -- so the date could never sit to the
                // right of the buttons while it was passed as `detail`.
                title: "Workflowy"
                meta: root.heroMeta
                foreground: root.foreground
                fontFamily: root.fontFamily
                metaOpacity: store.error !== "" ? 1.0 : 0.7
              }
            }

            Row {
              id: headerActions
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              BorderSurface {
                id: datePill
                // Quieter than the button beside it on purpose: this is a
                // label, and at full strength a bordered chip next to a
                // bordered button reads as a second thing to click.
                visible: store.label !== ""
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: dateText.implicitWidth + Style.space(10)
                implicitHeight: dateText.implicitHeight + Style.space(4)
                opacity: 0.55
                color: "transparent"
                borderSpec: Border.controlSpec("normal", root.dim, root.dim)
                radius: Style.cornerRadius

                Text {
                  id: dateText
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: store.label
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              PanelActionButton {
                id: menuButton
                iconText: "󰇙"
                tooltipText: "More"
                bordered: true
                // Squared off to the date chip's height rather than the 22px
                // default: it lines the two boxes up, and a 22px target for
                // the panel's only menu is meaner than it needs to be.
                size: Math.max(Style.space(22), datePill.implicitHeight)
                anchors.verticalCenter: parent.verticalCenter
                foreground: root.menuOpen || root.settingsOpen ? root.accent
                                                               : root.foreground
                onClicked: root.menuOpen = !root.menuOpen
              }
            }
          }

          // The menu sits in the column flow rather than floating: a popup
          // anchored inside a Flickable has to track scrolling, and there are
          // two entries.
          Item {
            width: parent.width
            visible: root.menuOpen
            implicitHeight: visible ? menuCard.implicitHeight : 0

            BorderSurface {
              id: menuCard
              anchors.right: parent.right
              implicitWidth: Math.min(parent.width, Style.space(230))
              implicitHeight: menuColumn.implicitHeight + Style.space(8)
              color: "transparent"
              borderSpec: Border.controlSpec("normal", root.foreground, root.accent)
              radius: Style.cornerRadius

              Column {
                id: menuColumn
                anchors.centerIn: parent
                width: parent.width - Style.space(8)

                MenuRow {
                  width: parent.width
                  label: store.loading ? "Refreshing…" : "Refresh"
                  glyph: "󰑐"
                  enabled: !store.loading
                  onTriggered: { root.refresh(); root.closeMenu() }
                }

                MenuRow {
                  width: parent.width
                  label: root.settingsOpen ? "Back to the list" : "Settings"
                  glyph: "󰒓"
                  onTriggered: root.toggleSettings()
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.settingsOpen

            TextField {
              id: capture
              width: parent.width - addButton.width - Style.space(8)
              placeholderText: root.sources[root.sourceIndex] === "inbox"
                ? "New item in Inbox…" : "New todo for today…"
              foreground: root.foreground
              onAccepted: root.submitCapture()
            }

            Button {
              id: addButton
              text: "Add"
              bordered: true
              enabled: capture.text.trim() !== ""
              opacity: enabled ? 1.0 : 0.4
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.submitCapture()
            }
          }

          ButtonGroup {
            width: parent.width
            visible: !root.settingsOpen
            options: root.sourceLabels
            // ButtonGroup speaks in labels, not indices, so the selected tab
            // round-trips through sourceLabels rather than being tracked twice.
            value: root.sourceLabels[root.sourceIndex]
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) {
              root.selectSource(root.sourceLabels.indexOf(value))
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            id: itemColumn
            visible: !root.settingsOpen
            width: parent.width
            spacing: Style.space(4)

            Repeater {
              model: store.visibleItems
              ItemRow {
                required property var modelData
                width: itemColumn.width
                item: modelData
              }
            }
          }

          PanelSeparator {
            visible: root.showFound && !root.settingsOpen
            foreground: root.foreground
          }

          Column {
            visible: root.showFound && !root.settingsOpen
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              // Workflowy's own name for these, so the two agree.
              text: "FOUND DATES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: foundColumn
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: store.visibleFound
                ItemRow {
                  required property var modelData
                  width: foundColumn.width
                  item: modelData
                }
              }
            }
          }

          Column {
            visible: root.settingsOpen
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "WORKFLOWY ACCOUNT"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: {
                if (!store.authLoaded) return "Checking…"
                if (!store.authConfigured)
                  return "No API token found. Paste one below — get it from "
                       + "workflowy.com/api-key"
                return (store.authOwn ? "Using the token saved here"
                                      : "Using the wf CLI's token")
                       + " (" + store.authHint + ")"
              }
              color: store.authLoaded && !store.authConfigured ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: tokenField
                width: parent.width - saveToken.width
                        - (forgetToken.visible ? forgetToken.width + Style.space(8) : 0)
                        - Style.space(8)
                // Masked: the panel can be open on a shared screen, and there
                // is never a reason to read a token back off it.
                password: true
                placeholderText: store.authConfigured ? "Replace the token…"
                                                      : "Paste your API token…"
                foreground: root.foreground
                onAccepted: { store.setToken(text); text = "" }
              }

              Button {
                id: saveToken
                text: "Save"
                bordered: true
                enabled: tokenField.text.trim() !== "" && !store.authSaving
                opacity: enabled ? 1.0 : 0.4
                foreground: root.foreground
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: { store.setToken(tokenField.text); tokenField.text = "" }
              }

              Button {
                id: forgetToken
                text: "Forget"
                bordered: true
                // Only when Omaflowy holds its own copy: with the wf CLI's
                // token there is nothing here to forget, and offering it would
                // imply this panel can revoke someone else's config.
                visible: store.authOwn
                enabled: !store.authSaving
                foreground: root.urgent
                fontFamily: root.fontFamily
                anchors.verticalCenter: parent.verticalCenter
                onClicked: store.clearToken()
              }
            }

            Text {
              visible: store.authError !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: store.authError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Verified with Workflowy before it is saved, to "
                    + "~/.config/omaflowy/token, readable only by you."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              opacity: 0.8
            }

            PanelSeparator { foreground: root.foreground }

            PanelSectionHeader {
              text: "KEYBOARD SHORTCUTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Capture opens on whichever tab was last shown. Press Enter "
                    + "in a field to save; changes reload Hyprland straight away."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            Column {
              id: bindColumn
              width: parent.width
              spacing: Style.space(12)

              Repeater {
                model: store.bindOrder
                BindRow {
                  required property var modelData
                  width: bindColumn.width
                  action: modelData
                }
              }
            }

            Text {
              visible: store.bindsError !== ""
              width: parent.width
              textFormat: Text.PlainText
              text: store.bindsError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "These only apply if hypr/omaflowy.lua is sourced from your "
                    + "bindings.lua. Written to ~/.config/omaflowy/binds.lua."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              opacity: 0.8
            }
          }

          Text {
            visible: store.everLoaded && store.error === "" && store.count === 0
                     && !root.showFound && !root.settingsOpen
            width: parent.width
            textFormat: Text.PlainText
            text: root.sources[root.sourceIndex] === "all"
              ? "No open todos anywhere."
              : "Nothing open. Type above to add the first one."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component MenuRow: CursorSurface {
    id: menuRow
    required property string label
    required property string glyph
    property bool enabled: true
    signal triggered()

    foreground: root.foreground
    implicitHeight: Style.space(30)
    opacity: enabled ? 1.0 : 0.4

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: menuRow.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        text: menuRow.label
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: menuRow.enabled
      onEntered: menuRow.hasCursor = true
      onExited: menuRow.hasCursor = false
      onClicked: menuRow.triggered()
    }
  }

  component BindRow: Column {
    id: bindRow
    required property string action

    readonly property var entry: store.binds[action] || ({})
    readonly property bool enabled: entry.enabled !== false
    readonly property string conflict: String(store.bindConflicts[action] || "")

    spacing: Style.space(4)

    function commit(key, on) {
      var payload = {}
      payload[bindRow.action] = { key: key, enabled: on }
      store.saveBinds(payload)
    }

    Row {
      width: parent.width
      spacing: Style.space(8)

      Text {
        width: parent.width - toggle.width - keyField.width - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: store.bindLabels[bindRow.action] || bindRow.action
        color: bindRow.enabled ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      TextField {
        id: keyField
        width: Style.space(170)
        anchors.verticalCenter: parent.verticalCenter
        enabled: bindRow.enabled
        opacity: bindRow.enabled ? 1.0 : 0.45
        foreground: root.foreground
        placeholderText: "SUPER + ALT + W"
        // Bound one way only. Binding `text` straight to the store would
        // rewrite the box under the cursor on every save round-trip, so it is
        // seeded on load and on external change, then left alone while typing.
        Component.onCompleted: text = bindRow.entry.key || ""
        Connections {
          target: store
          function onBindsChanged() {
            if (!keyField.activeFocus) keyField.text = bindRow.entry.key || ""
          }
        }
        onAccepted: bindRow.commit(text, true)
      }

      ToggleSwitch {
        id: toggle
        anchors.verticalCenter: parent.verticalCenter
        checked: bindRow.enabled
        busy: store.bindsSaving
        foreground: root.foreground
        onToggled: bindRow.commit(keyField.text, !bindRow.enabled)
      }
    }

    Text {
      // Hyprland takes a duplicate bind and the later one silently wins, so
      // this warning is the only place a collision is ever visible.
      visible: bindRow.enabled && bindRow.conflict !== ""
      width: parent.width
      textFormat: Text.PlainText
      text: "Already used by " + bindRow.conflict + " — the later bind wins"
      color: root.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  component ItemRow: CursorSurface {
    id: row
    required property var item

    foreground: root.foreground
    implicitHeight: rowText.implicitHeight + Style.space(10)

    Row {
      id: rowLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      PanelActionButton {
        id: completeButton
        iconText: hovered ? "\udb80\udd32" : "\udb80\udd30"
        tooltipText: "Complete"
        foreground: hovered ? root.accent : root.foreground
        fontSize: Style.font.body
        // Aligned to the first line rather than the block's centre: a wrapped
        // two-line todo with its path underneath left the control floating
        // beside the second line, reading as though it belonged elsewhere.
        anchors.top: parent.top
        anchors.topMargin: Math.max(0, (rowText.firstLineHeight - height) / 2)
        property bool hovered: false
        onHovered: function(on) { hovered = on }
        onClicked: store.complete(row.item.id)
      }

      // Two targets, each doing the obvious thing: the circle ticks it off,
      // the words take you to it. A row-wide click that completed would put
      // the destructive action under the cursor everywhere, which is the wrong
      // default for a list you mostly scan.
      Item {
        width: rowLayout.width - completeButton.width - Style.space(8)
                 - (moveButton.visible ? moveButton.width + Style.space(8) : 0)
        implicitHeight: rowText.implicitHeight

        Column {
          id: rowText
          width: parent.width
          spacing: Style.space(2)

          readonly property real firstLineHeight:
            label.lineCount > 0 ? label.implicitHeight / label.lineCount
                                : label.implicitHeight

          Text {
            id: label
            width: parent.width
            textFormat: Text.PlainText
            // A found date can carry a time of day; it is the only thing that
            // orders the section, so it belongs on the line itself.
            text: String(row.item.at || "") !== ""
              ? row.item.at + "  " + row.item.text : row.item.text
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
          }

          Text {
            // Where it sits in the tree. Without it "start the team check-ins"
            // reads as a free-floating order with no clue which client or
            // section it belongs to -- and in the All view, no clue which day.
            visible: String(row.item.path || "") !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: row.item.path
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            opacity: 0.75
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: row.hasCursor = true
          onExited: row.hasCursor = false
          onClicked: root.openNode(row.item.id)
        }
      }

      PanelActionButton {
        id: moveButton
        iconText: root.todayIcon
        tooltipText: "Move to today"
        foreground: hovered ? root.accent : root.dim
        fontSize: Style.font.body
        visible: root.canMove
        // Present but quiet, rather than hover-only. A control that is
        // invisible until the cursor lands on the right row is a control most
        // people never find, and this one is the whole point of the Inbox tab.
        opacity: row.hasCursor || hovered ? 1.0 : 0.35
        anchors.top: parent.top
        anchors.topMargin: Math.max(0, (rowText.firstLineHeight - height) / 2)
        property bool hovered: false
        Behavior on opacity { NumberAnimation { duration: 100 } }
        onHovered: function(on) { hovered = on }
        onClicked: store.moveToToday(row.item.id)
      }
    }

    PanelToolTip {
      visible: row.hasCursor
      text: row.item.note !== "" ? row.item.note : "Open in Workflowy"
      fontFamily: root.fontFamily
    }
  }
}
