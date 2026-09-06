import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The day's todos, the whole history behind them, and the clock that decides
// how far behind you are. One of these lives per bar instance; they all watch
// the same file, so a change made on one monitor shows up on the others
// without any cross-instance plumbing.
Item {
  id: root

  // The window the day is measured against. Progress is judged against how
  // much of *this* has elapsed, not against midnight.
  property int dayStartHour: 8
  property int dayEndHour: 22

  readonly property string directory: Quickshell.env("HOME") + "/.local/share/omarchy-todos"
  readonly property string path: directory + "/history.json"

  property var state: Model.emptyState()
  property bool loaded: false
  property bool directoryReady: false
  property bool writePending: false

  property date now: new Date()
  property string todayKey: Model.dayKey(new Date())

  readonly property var today: state.days[todayKey] || Model.emptyDay(todayKey)
  readonly property var stats: Model.dayStats(today)
  readonly property real dayFraction: Model.dayFraction(now, dayStartHour, dayEndHour)
  readonly property var mood: Model.moodFor(stats, dayFraction, now.getHours())
  readonly property int streak: Model.streak(state, todayKey)
  readonly property var history: Model.historySeries(state, todayKey, 14)
  readonly property var lifetime: Model.totals(state)

  readonly property bool big3Full: today.big3.length >= 3

  signal rolledOver(int carried)

  function nowIso() {
    return new Date().toISOString()
  }

  // --------------------------------------------------------------- lifecycle

  function adopt(raw) {
    var read = Model.readState(raw)

    // Refuse to act on a read we cannot trust. Both branches keep the state we
    // already have and, crucially, write nothing: persisting a bad read is how
    // a torn file turns into lost history.
    if (!read.ok) {
      console.warn("saikomantisu.todos: history file did not parse; keeping the loaded state")
      return
    }
    if (read.empty && Model.dayCount(root.state) > 0) {
      console.warn("saikomantisu.todos: history file read back empty; keeping the loaded state")
      return
    }

    var rolled = Model.rollForward(read.state, root.todayKey)
    root.state = rolled.state
    root.loaded = true
    if (rolled.created) {
      persist()
      if (rolled.carried > 0) root.rolledOver(rolled.carried)
    }
  }

  function persist() {
    if (!root.directoryReady) {
      root.writePending = true
      return
    }
    root.writePending = false
    file.setText(Model.serializeState(root.state))
  }

  function mutate(next) {
    if (!next || next === root.state) return
    root.state = next
    persist()
  }

  // Midnight (or a resume from suspend) lands here: re-key the day, which
  // pulls whatever was left unfinished into the new one.
  function tick() {
    root.now = clock.date
    var key = Model.dayKey(clock.date)
    if (key === root.todayKey) return

    root.todayKey = key
    var rolled = Model.rollForward(root.state, key)
    if (!rolled.created) return
    root.state = rolled.state
    persist()
    if (rolled.carried > 0) root.rolledOver(rolled.carried)
  }

  // --------------------------------------------------------------- mutations

  function add(kind, text) {
    mutate(Model.addItem(root.state, root.todayKey, kind, text, nowIso()))
  }

  function toggle(kind, id) {
    mutate(Model.toggleItem(root.state, root.todayKey, kind, id, nowIso()))
  }

  function remove(kind, id) {
    mutate(Model.removeItem(root.state, root.todayKey, kind, id))
  }

  function rename(kind, id, text) {
    mutate(Model.renameItem(root.state, root.todayKey, kind, id, text))
  }

  // Big 3 <-> regular. Promotion is a no-op when all three slots are taken.
  function shift(kind, id) {
    mutate(Model.moveItem(root.state, root.todayKey, kind, id))
  }

  function reorder(kind, id, delta) {
    mutate(Model.reorderItem(root.state, root.todayKey, kind, id, delta))
  }

  function clearCompleted() {
    mutate(Model.clearCompleted(root.state, root.todayKey))
  }

  // ------------------------------------------------------------- persistence

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.tick()
  }

  FileView {
    id: file
    path: root.path
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.adopt(text())
    // First run: no file yet. Adopting an empty history creates today and
    // writes it, which is also what creates the file.
    onLoadFailed: root.adopt("")
    onFileChanged: reload()
  }

  // FileView can't create the directory it writes into, and on a fresh install
  // nothing else owns this path.
  Process {
    id: ensureDirectory
    command: ["mkdir", "-p", root.directory]
    onExited: {
      root.directoryReady = true
      if (root.writePending) root.persist()
      else file.reload()
    }
  }

  Component.onCompleted: ensureDirectory.running = true
}
