import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget: Pip the mascot and today's count.
//
// The mascot is the ambient signal — you read the face without stopping — and
// the count is the exact number. Left click opens the day; the panel is where
// anything actually gets edited, and where the progress bar lives.
BarWidget {
  id: root
  moduleName: "saikomantisu.todos"

  readonly property int dayStartHour: Math.round(Number(setting("dayStart", 8)))
  readonly property int dayEndHour: Math.round(Number(setting("dayEnd", 22)))
  readonly property bool showCount: setting("showCount", true) === true

  readonly property var stats: store.stats
  readonly property var mood: store.mood
  readonly property string countText: stats.total > 0 ? stats.done + "/" + stats.total : "–"

  readonly property real mascotSize: Math.round(Style.bar.iconCanvas * 1.2)

  // ---- panel plumbing. Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root, so the widget stands in for the panel it hosts.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function openForCapture() { if (panelLoader.item) panelLoader.item.openForCapture() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("store" in target) target.store = store
  }

  function toggleCount() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.showCount = !root.showCount

    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Store {
    id: store
    dayStartHour: root.dayStartHour
    dayEndHour: root.dayEndHour

    // Only one instance should speak. The bar hands out widget instances per
    // monitor and they all watch the same file, so without this the same
    // rollover fires a notification per screen.
    onRolledOver: function(carried) {
      if (!root.bar || typeof root.bar.moduleWidgets !== "function") return
      var peers = root.bar.moduleWidgets(root.moduleName)
      if (peers.length > 0 && peers[0] !== root) return
      // execArgv, not bar.run: the message is built from data, and argv never
      // gets re-tokenized by the shell.
      Util.execArgv(["omarchy-notification-send", "--app-name", "Todos", "Carried into today",
        carried + (carried === 1 ? " unfinished todo" : " unfinished todos") + " came across from your last day"])
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "saikomantisu.todos"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function capture(): void { root.openForCapture() }
    function add(text: string): void { store.add("todos", text) }
    function big3(text: string): void { store.add("big3", text) }
    function status(): string {
      return store.stats.done + "/" + store.stats.total + " " + store.mood.label
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    horizontalMargin: 7
    fixedWidth: root.vertical ? -1 : Math.round(content.implicitWidth + Style.spaceReal(7) * 2)
    fixedHeight: root.vertical ? Math.round(content.implicitHeight + Style.spaceReal(4) * 2) : -1
    tooltipText: root.stats.total > 0
      ? root.mood.label + " · " + root.stats.done + " of " + root.stats.total + " done"
        + (root.stats.big3Total > 0 ? " (Big 3: " + root.stats.big3Done + "/" + root.stats.big3Total + ")" : "")
      : "No todos planned for today"

    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleCount()
      else if (b === Qt.MiddleButton) root.openForCapture()
      else root.togglePanel()
    }

    // Mascot, with the count beside it. A vertical bar has no room for the
    // label, so the Row collapses to just Pip.
    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      Mascot {
        id: mascot
        width: root.mascotSize
        height: root.mascotSize
        anchors.verticalCenter: parent.verticalCenter
        baseColor: root.bar ? root.bar.barForeground : Color.foreground
        alertColor: root.bar ? root.bar.urgent : Color.urgent
        animated: root.visible

        urgency: root.mood.urgency
        smile: root.mood.smile
        eyes: root.mood.eyes
        brow: root.mood.brow
        sweat: root.mood.sweat
        sparkle: root.mood.sparkle
        wavy: root.mood.wavy
      }

      Text {
        id: countLabel
        visible: root.showCount && !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.countText
        color: mascot.inkColor
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.bodySmall
        renderType: Text.NativeRendering

        Behavior on color { ColorAnimation { duration: 200 } }
      }
    }
  }
}
