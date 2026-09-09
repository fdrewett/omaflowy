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
  moduleName: "frank.omaflowy"
  ipcTarget: "omaflowy"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool showNotes: setting("showNotes", true)
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", false)
  readonly property var visibleNotes: showNotes ? store.notes : []

  // The pill counts todos only. A leaf bullet under today is as often
  // narrative ("dinner with the folks") as it is work, so counting those
  // would put a number in the bar that does not mean anything.
  readonly property int pillCount: store.todos.length
  readonly property string pillText:
    store.error !== "" ? "󰅚" : (store.everLoaded ? "󰄱 " + pillCount : "󰄱 ·")

  readonly property string heroMeta: {
    if (store.error !== "") return store.error
    if (!store.everLoaded) return "Loading…"
    if (pillCount === 0 && visibleNotes.length === 0) return "Nothing open"
    var parts = [pillCount + (pillCount === 1 ? " todo" : " todos")]
    if (visibleNotes.length > 0) parts.push(visibleNotes.length + " other")
    return parts.join(" · ")
  }

  function refresh() { store.refresh() }

  function openInWorkflowy() {
    // The day node is addressable by date in the API but not in a web URL, so
    // this lands on the calendar rather than deep-linking to today.
    if (bar) bar.run("xdg-open https://workflowy.com/#/")
  }

  Store {
    id: store
    depth: root.setting("depth", 4)
    exclude: root.setting("excludePaths", "")
  }

  Component.onCompleted: store.refresh()

  Timer {
    // Two rates, the pattern harshith.system-monitor uses: a slow beat to keep
    // the pill honest, a faster one while someone is looking at the list.
    interval: 1000 * (root.opened
      ? root.setting("openRefreshSec", 60)
      : root.setting("refreshSec", 300))
    running: true
    repeat: true
    onTriggered: store.refresh()
  }

  Connections {
    target: root
    // Opening should not show a stale list, but re-fetching on every toggle
    // would hammer the API when the panel is being flicked open and shut.
    function onOpenedChanged() {
      if (root.opened && Date.now() / 1000 - store.fetchedAt > 30) store.refresh()
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
    function count(): string { return String(root.pillCount) }
  }

  visible: !(root.hideWhenEmpty && store.everLoaded
             && root.pillCount === 0 && root.visibleNotes.length === 0)
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
      if (buttonCode === Qt.RightButton) root.openInWorkflowy()
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
    contentWidth: popup.fittedContentWidth(Style.space(400))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // The capture field wants every keystroke it can get, so the catcher
      // stands down while it has focus — otherwise typing "r" in a todo would
      // fire the refresh shortcut instead of landing in the text.
      blocked: capture.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "n" || t === "N") capture.forceActiveFocus()
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
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Today"
            meta: root.heroMeta
            detail: store.date
            foreground: root.foreground
            fontFamily: root.fontFamily
            metaOpacity: store.error !== "" ? 1.0 : 0.7

            trailingControl: Component {
              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh"
                foreground: root.foreground
                enabled: !store.loading
                opacity: store.loading ? 0.4 : 1.0
                onClicked: root.refresh()
              }
            }
          }

          TextField {
            id: capture
            width: parent.width
            placeholderText: "New todo…"
            foreground: root.foreground
            onAccepted: {
              if (text.trim() === "") return
              store.add(text)
              text = ""
            }
          }

          PanelSeparator {
            visible: store.todos.length > 0
            foreground: root.foreground
          }

          Column {
            visible: store.todos.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "OPEN"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: todoColumn
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: store.todos
                ItemRow {
                  required property var modelData
                  width: todoColumn.width
                  item: modelData
                  isTodo: true
                }
              }
            }
          }

          PanelSeparator {
            visible: root.visibleNotes.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.visibleNotes.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "FROM TODAY'S NOTES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: noteColumn
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.visibleNotes
                ItemRow {
                  required property var modelData
                  width: noteColumn.width
                  item: modelData
                  isTodo: false
                }
              }
            }
          }

          Text {
            visible: store.everLoaded && store.error === ""
                     && store.todos.length === 0 && root.visibleNotes.length === 0
            width: parent.width
            textFormat: Text.PlainText
            text: "Nothing open under today. Type above to add the first one."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component ItemRow: CursorSurface {
    id: row
    required property var item
    required property bool isTodo

    readonly property bool busy: store.isPending(row.item.id)

    foreground: root.foreground
    implicitHeight: rowText.implicitHeight + Style.space(10)
    opacity: busy ? 0.35 : 1.0

    Behavior on opacity { NumberAnimation { duration: 120 } }

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        // A todo gets a real box; a plain bullet gets a dot, so the two lists
        // stay distinguishable after they scroll apart from their headers.
        text: row.isTodo ? "󰄱" : "·"
        color: row.isTodo ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: rowText
        width: parent.width - Style.space(24)
        spacing: Style.space(2)

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: row.item.text
          color: row.isTodo ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }

        Text {
          // Where it sits under today. Without it "Cancel the trial" and
          // "start the team check-ins" read as free-floating orders with no
          // clue which client or section they belong to.
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
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      enabled: !row.busy
      onEntered: row.hasCursor = true
      onExited: row.hasCursor = false
      onClicked: store.complete(row.item.id)
    }

    PanelToolTip {
      visible: row.hasCursor
      text: row.item.note !== "" ? row.item.note : "Click to complete"
      fontFamily: root.fontFamily
    }
  }
}
