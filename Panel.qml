import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The day: Pip at full size, the progress bar, the Big 3, everything else,
// and a two-week strip of what the days behind this one looked like.
//
// The bar widget owns the store and the IPC target; this panel is a view over
// them plus the editing affordances.
Panel {
  id: root
  moduleName: "io.github.saikomantisu.todos"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var store: null

  // The bar tracks the widget mounted in its slot, not this nested panel, so
  // everything the bar identifies a panel by has to be that widget.
  readonly property var barIdentity: hostWidget || root

  readonly property var today: store ? store.today : Model.emptyDay("")
  readonly property var stats: store ? store.stats : Model.dayStats(null)
  readonly property var mood: store ? store.mood : Model.moodFor(Model.dayStats(null), 0, 0)
  readonly property real dayFraction: store ? store.dayFraction : 0
  readonly property var history: store ? store.history : []
  readonly property int streakDays: store ? store.streak : 0
  readonly property var lifetime: store ? store.lifetime : ({ completed: 0, planned: 0, days: 0 })
  readonly property date now: store ? store.now : new Date()

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  // ---- keyboard cursor ------------------------------------------------
  // One flat list across both sections so Up/Down walks the whole day.
  property int cursorIndex: -1
  property string editingKind: ""
  property string editingId: ""
  property bool captureRequested: false

  readonly property var rows: {
    var out = []
    var i
    for (i = 0; i < today.big3.length; i++) out.push({ kind: "big3", id: today.big3[i].id })
    for (i = 0; i < today.todos.length; i++) out.push({ kind: "todos", id: today.todos[i].id })
    return out
  }

  function cursorRow() {
    return cursorIndex >= 0 && cursorIndex < rows.length ? rows[cursorIndex] : null
  }

  function isCursor(kind, id) {
    var row = cursorRow()
    return !!row && row.kind === kind && row.id === id
  }

  function moveCursor(delta) {
    if (rows.length === 0) return
    if (cursorIndex < 0) {
      cursorIndex = delta > 0 ? 0 : rows.length - 1
      return
    }
    cursorIndex = Math.max(0, Math.min(rows.length - 1, cursorIndex + delta))
  }

  function activateCursor() {
    var row = cursorRow()
    if (row && store) store.toggle(row.kind, row.id)
  }

  function deleteCursor() {
    var row = cursorRow()
    if (!row || !store) return
    store.remove(row.kind, row.id)
    cursorIndex = Math.min(cursorIndex, rows.length - 2)
  }

  function shiftCursor() {
    var row = cursorRow()
    if (row && store) store.shift(row.kind, row.id)
  }

  function reorderCursor(delta) {
    var row = cursorRow()
    if (row && store) store.reorder(row.kind, row.id, delta)
  }

  function beginEdit(kind, id) {
    editingKind = kind
    editingId = id
  }

  function endEdit(commitText) {
    if (editingId !== "" && store && commitText !== undefined) store.rename(editingKind, editingId, commitText)
    editingKind = ""
    editingId = ""
    Qt.callLater(function() { if (root.opened) keyCatcher.forceActiveFocus() })
  }

  // ---- lifecycle -------------------------------------------------------

  function open() {
    captureRequested = false
    root.controller.show()
  }

  // Middle click on the widget and the `capture` IPC method land here: open
  // straight into the add field, so a thought can be dumped without aiming.
  function openForCapture() {
    captureRequested = true
    root.controller.show()
    Qt.callLater(function() { if (root.opened) todoInput.focusInput() })
  }

  function close() {
    editingKind = ""
    editingId = ""
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  onOpenedChanged: {
    if (opened) {
      cursorIndex = -1
      if (captureRequested) Qt.callLater(function() { if (root.opened) todoInput.focusInput() })
    } else {
      captureRequested = false
    }
  }

  implicitWidth: 0
  implicitHeight: 0

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // Any live text input owns the keyboard; otherwise typing "j" in a todo
      // would move the cursor instead of writing a j.
      blocked: root.editingId !== "" || big3Input.inputFocused || todoInput.inputFocused

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.shiftCursor()
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onDeleteRequested: root.deleteCursor()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "a") { todoInput.focusInput(); return }
        if (text === "b") { big3Input.focusInput(); return }
        if (text === "e") { var row = root.cursorRow(); if (row) root.beginEdit(row.kind, row.id); return }
        if (text === "K") { root.reorderCursor(-1); return }
        if (text === "J") { root.reorderCursor(1); return }
        if (text === "c" && root.store) root.store.clearCompleted()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- hero: mascot · date/mood · count ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroMascot.height, heroLabels.implicitHeight, heroCount.implicitHeight)

          Mascot {
            id: heroMascot
            width: Style.space(58)
            height: Style.space(58)
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            baseColor: root.fg
            alertColor: root.bar ? root.bar.urgent : Color.urgent
            animated: root.opened

            urgency: root.mood.urgency
            smile: root.mood.smile
            eyes: root.mood.eyes
            brow: root.mood.brow
            sweat: root.mood.sweat
            sparkle: root.mood.sparkle
            wavy: root.mood.wavy
          }

          Column {
            id: heroLabels
            anchors.left: heroMascot.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroCount.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: Qt.formatDate(root.now, "dddd d MMMM")
              color: root.fg
              font.family: root.family
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.mood.label.toUpperCase()
              color: heroMascot.inkColor
              font.family: root.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width

              Behavior on color { ColorAnimation { duration: 220 } }
            }

            Text {
              textFormat: Text.PlainText
              text: root.mood.tagline
              color: Qt.darker(root.fg, 1.4)
              font.family: root.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroCount
            textFormat: Text.PlainText
            text: root.stats.total > 0 ? root.stats.done + "/" + root.stats.total : "—"
            color: root.fg
            font.family: root.family
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // ---------- day progress ----------
        Column {
          width: parent.width
          spacing: Style.space(5)

          Item {
            width: parent.width
            implicitHeight: Style.space(9)

            Rectangle {
              id: heroTrack
              anchors.fill: parent
              radius: height / 2
              color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
            }

            Rectangle {
              anchors.left: heroTrack.left
              anchors.verticalCenter: heroTrack.verticalCenter
              height: heroTrack.height
              radius: heroTrack.radius
              width: Math.max(root.stats.done > 0 ? heroTrack.height : 0, heroTrack.width * root.stats.ratio)
              color: heroMascot.inkColor

              Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
              Behavior on color { ColorAnimation { duration: 220 } }
            }

            // Where the clock says you should be. The gap between this and
            // the fill is exactly what the mascot's face is reacting to.
            Rectangle {
              visible: root.stats.total > 0 && !root.stats.allDone
              width: Math.max(1, Style.space(2))
              height: parent.height + Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              x: Math.min(parent.width - width, Math.round(parent.width * root.dayFraction))
              color: root.fg
              opacity: 0.85

              Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
            }
          }

          Item {
            width: parent.width
            implicitHeight: progressCaption.implicitHeight

            Text {
              id: progressCaption
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: root.stats.total > 0
                ? Math.round(root.stats.ratio * 100) + "% of today done"
                : "Nothing planned yet"
              color: Qt.darker(root.fg, 1.5)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: Math.round(root.dayFraction * 100) + "% of the day gone"
              color: Qt.darker(root.fg, 1.5)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- the big 3 ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: big3Header.implicitHeight

            PanelSectionHeader {
              id: big3Header
              anchors.left: parent.left
              text: "THE BIG 3"
              foreground: root.fg
              fontFamily: root.family
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: big3Header.verticalCenter
              textFormat: Text.PlainText
              text: root.stats.big3Done + "/" + Math.max(1, root.stats.big3Total)
              color: Qt.darker(root.fg, 1.5)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }

          Repeater {
            model: root.today.big3

            ItemRow {
              required property var modelData
              required property int index
              width: column.width
              kind: "big3"
              item: modelData
              ordinal: index + 1
            }
          }

          // The next free slot is the input itself — no separate "add" button
          // to hunt for, and the remaining slots stay visible as ghosts so the
          // cap on three stays part of the picture.
          AddRow {
            id: big3Input
            visible: root.today.big3.length < 3
            width: column.width
            placeholder: "Big thing #" + (root.today.big3.length + 1)
            ordinal: root.today.big3.length + 1
            onSubmitted: function(text) { if (root.store) root.store.add("big3", text) }
          }

          Repeater {
            model: Math.max(0, 3 - root.today.big3.length - 1)

            Item {
              required property int index
              width: column.width
              implicitHeight: Style.spacing.popupRowHeight

              Row {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: Style.space(2)
                spacing: Style.space(9)
                opacity: 0.3

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: String(root.today.big3.length + index + 2) + "."
                  color: root.fg
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  textFormat: Text.PlainText
                  text: "empty slot"
                  color: root.fg
                  font.family: root.family
                  font.pixelSize: Style.font.bodySmall
                  font.italic: true
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- everything else ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: todoHeader.implicitHeight

            PanelSectionHeader {
              id: todoHeader
              anchors.left: parent.left
              text: "TODOS"
              foreground: root.fg
              fontFamily: root.family
            }

            Text {
              id: clearDone
              anchors.right: parent.right
              anchors.verticalCenter: todoHeader.verticalCenter
              visible: root.stats.todoDone > 0
              textFormat: Text.PlainText
              text: "clear " + root.stats.todoDone + " done"
              color: clearArea.containsMouse ? root.fg : Qt.darker(root.fg, 1.5)
              font.family: root.family
              font.pixelSize: Style.font.caption

              MouseArea {
                id: clearArea
                anchors.fill: parent
                anchors.margins: -Style.space(4)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.store) root.store.clearCompleted()
              }
            }
          }

          // Long days scroll instead of pushing the panel off screen.
          Flickable {
            width: parent.width
            height: Math.min(todoList.implicitHeight, Style.space(216))
            contentHeight: todoList.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
              id: todoList
              width: parent.width

              Repeater {
                model: root.today.todos

                ItemRow {
                  required property var modelData
                  required property int index
                  width: todoList.width
                  kind: "todos"
                  item: modelData
                  ordinal: 0
                }
              }
            }
          }

          AddRow {
            id: todoInput
            width: column.width
            placeholder: root.today.todos.length === 0 ? "Add a todo…" : "Add another…"
            ordinal: 0
            onSubmitted: function(text) { if (root.store) root.store.add("todos", text) }
          }
        }

        PanelSeparator { foreground: root.fg }

        // ---------- history ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "LAST 14 DAYS"
            foreground: root.fg
            fontFamily: root.family
          }

          Row {
            width: parent.width
            height: Style.space(26)
            spacing: Math.max(1, Style.space(3))

            Repeater {
              model: root.history

              Item {
                required property var modelData
                required property int index
                width: (parent.width - parent.spacing * (root.history.length - 1)) / Math.max(1, root.history.length)
                height: parent.height

                readonly property bool isToday: index === root.history.length - 1
                readonly property real ratio: modelData.stats.ratio

                Rectangle {
                  id: histTrack
                  anchors.fill: parent
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius : Math.round(width / 3)
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, modelData.tracked ? 0.12 : 0.06)
                }

                Rectangle {
                  anchors.bottom: histTrack.bottom
                  anchors.left: histTrack.left
                  anchors.right: histTrack.right
                  radius: histTrack.radius
                  height: Math.round(histTrack.height * ratio)
                  color: root.fg
                  opacity: modelData.stats.allDone ? 0.95 : 0.55
                }

                Rectangle {
                  visible: isToday
                  anchors.fill: histTrack
                  radius: histTrack.radius
                  color: "transparent"
                  border.width: Math.max(1, Style.space(1))
                  border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.6)
                }
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: historyCaption.implicitHeight

            Text {
              id: historyCaption
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: root.streakDays > 0
                ? root.streakDays + (root.streakDays === 1 ? " day clear" : " days clear in a row")
                : "No streak yet"
              color: Qt.darker(root.fg, 1.5)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.lifetime.completed + " of " + root.lifetime.planned + " all time"
              color: Qt.darker(root.fg, 1.5)
              font.family: root.family
              font.pixelSize: Style.font.caption
            }
          }
        }

        // ---------- key legend ----------
        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "↑↓ move · space done · e edit · x delete · a add"
          color: Qt.darker(root.fg, 1.7)
          font.family: root.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // ------------------------------------------------------------- components

  // One todo. Checkbox, text, and the two actions that only appear when the
  // row is under the pointer or the keyboard cursor.
  component ItemRow: Item {
    id: row

    property string kind: "todos"
    property var item: null
    property int ordinal: 0

    readonly property bool done: item ? item.done === true : false
    readonly property bool cursor: item ? root.isCursor(kind, item.id) : false
    readonly property bool editing: item ? root.editingId === item.id : false
    readonly property bool hot: cursor || hover.containsMouse

    implicitHeight: Style.spacing.popupRowHeight
    height: implicitHeight

    Rectangle {
      anchors.fill: parent
      anchors.leftMargin: -Style.space(6)
      anchors.rightMargin: -Style.space(6)
      radius: Style.cornerRadius
      color: row.hot ? Style.hoverFillFor(root.fg, root.fg) : "transparent"
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      enabled: !row.editing

      onEntered: {
        var index = -1
        for (var i = 0; i < root.rows.length; i++)
          if (root.rows[i].kind === row.kind && root.rows[i].id === row.item.id) index = i
        if (index >= 0) root.cursorIndex = index
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.beginEdit(row.kind, row.item.id)
        else if (root.store) root.store.toggle(row.kind, row.item.id)
      }
      onDoubleClicked: root.beginEdit(row.kind, row.item.id)
    }

    Row {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(2)
      anchors.right: actions.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(9)

      Text {
        visible: row.ordinal > 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: row.ordinal + "."
        color: root.fg
        opacity: row.done ? 0.35 : 0.55
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
      }

      Rectangle {
        id: box
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(15)
        height: width
        radius: row.kind === "big3" ? width / 2 : (Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(3))
        color: row.done ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.85) : "transparent"
        border.width: Math.max(1, Style.space(1))
        border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, row.done ? 0.85 : (row.hot ? 0.75 : 0.4))

        Behavior on color { ColorAnimation { duration: 140 } }

        Text {
          anchors.centerIn: parent
          visible: row.done
          textFormat: Text.PlainText
          text: "✓"
          color: Color.popups.background
          font.family: root.family
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      Text {
        id: label
        visible: !row.editing
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - x)
        textFormat: Text.PlainText
        text: row.item ? row.item.text : ""
        color: root.fg
        opacity: row.done ? 0.45 : 1
        font.family: root.family
        font.pixelSize: Style.font.body
        font.strikeout: row.done
        elide: Text.ElideRight
      }

      TextField {
        id: editor
        visible: row.editing
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - x)
        foreground: root.fg
        accent: root.bar ? root.bar.foreground : Color.accent
        verticalPadding: Style.space(2)
        font.pixelSize: Style.font.body

        onVisibleChanged: if (visible) {
          text = row.item ? row.item.text : ""
          Qt.callLater(function() { editor.forceActiveFocus(); editor.selectAll() })
        }

        Keys.onEscapePressed: root.endEdit(undefined)
        onAccepted: root.endEdit(text)
        onActiveFocusChanged: if (!activeFocus && row.editing) root.endEdit(text)
      }
    }

    // Carry badge plus the row actions. A todo that has survived several
    // mornings says so, because that is usually the useful signal.
    Row {
      id: actions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)

      Text {
        visible: !!row.item && row.item.carries > 0 && !row.done
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "↻" + row.item.carries
        color: row.item && row.item.carries >= 3
          ? (root.bar ? root.bar.urgent : Color.urgent)
          : Qt.darker(root.fg, 1.5)
        font.family: root.family
        font.pixelSize: Style.font.caption
      }

      RowAction {
        anchors.verticalCenter: parent.verticalCenter
        visible: row.hot && !row.editing && (row.kind === "big3" || !root.store || !root.store.big3Full)
        glyph: row.kind === "big3" ? "▾" : "▴"
        tip: row.kind === "big3" ? "Move out of the Big 3" : "Promote to the Big 3"
        onTriggered: if (root.store) root.store.shift(row.kind, row.item.id)
      }

      RowAction {
        anchors.verticalCenter: parent.verticalCenter
        visible: row.hot && !row.editing
        glyph: "✕"
        tip: "Delete"
        onTriggered: if (root.store) root.store.remove(row.kind, row.item.id)
      }
    }
  }

  component RowAction: Item {
    id: action

    property string glyph: ""
    property string tip: ""
    signal triggered()

    width: Style.space(16)
    height: Style.space(16)

    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: action.glyph
      color: root.fg
      opacity: actionHover.containsMouse ? 1 : 0.5
      font.family: root.family
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: actionHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: action.triggered()
    }
  }

  // The next empty slot, as an input. Enter commits and keeps focus so a
  // brain-dump of five todos is five lines and no mouse.
  component AddRow: Item {
    id: adder

    property string placeholder: ""
    property int ordinal: 0
    readonly property bool inputFocused: field.activeFocus
    signal submitted(string text)

    function focusInput() { field.forceActiveFocus() }

    implicitHeight: Style.spacing.popupRowHeight
    height: implicitHeight

    Row {
      anchors.fill: parent
      anchors.leftMargin: Style.space(2)
      spacing: Style.space(9)

      Text {
        visible: adder.ordinal > 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: adder.ordinal + "."
        color: root.fg
        opacity: 0.4
        font.family: root.family
        font.pixelSize: Style.font.bodySmall
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: "+"
        color: root.fg
        opacity: field.activeFocus ? 0.9 : 0.4
        font.family: root.family
        font.pixelSize: Style.font.body
        width: Style.space(15)
        horizontalAlignment: Text.AlignHCenter
      }

      TextField {
        id: field
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(0, parent.width - x - Style.space(2))
        placeholderText: adder.placeholder
        foreground: root.fg
        accent: root.bar ? root.bar.foreground : Color.accent
        verticalPadding: Style.space(2)
        font.pixelSize: Style.font.body

        onAccepted: {
          var value = text
          text = ""
          adder.submitted(value)
        }

        Keys.onEscapePressed: {
          text = ""
          keyCatcher.forceActiveFocus()
        }
      }
    }
  }
}
