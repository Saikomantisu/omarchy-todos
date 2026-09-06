// Pure day/todo math for the Daily Todos widget, its mascot, and its panel.
//
// Everything here is Qt-free so the rollover and mood rules can be reasoned
// about (and tested) on their own: `node -e 'var M = require("./Model.js")'`
// style. The QML owns files, clocks, and painting; this file owns what a day
// means.
//
// The shape persisted to disk:
//
//   { "version": 1, "days": { "2026-09-06": { date, big3: [item], todos: [item] } } }
//
// and an item:
//
//   { id, text, done, createdAt, completedAt, firstSeen, carriedFrom, carries }
//
// Days are never rewritten once they are in the past, so the file doubles as
// the history: an unfinished todo stays unfinished on the day it was missed
// and is *copied* forward, rather than moved.

var VERSION = 1

// A Big 3 item counts double when measuring how far through the day's work
// you are. Finishing the three things that matter should move the needle more
// than clearing three small ones.
var BIG3_WEIGHT = 2

var BIG3_SLOTS = 3
var MAX_TODOS = 100
var MAX_TEXT = 200
var HISTORY_DAYS = 400

// ---------------------------------------------------------------- utilities

function clamp01(value) {
  var n = Number(value)
  if (!isFinite(n)) return 0
  return n < 0 ? 0 : (n > 1 ? 1 : n)
}

function pad2(n) {
  return n < 10 ? "0" + n : String(n)
}

var idCounter = 0

function newId() {
  idCounter += 1
  return "t" + Date.now().toString(36) + idCounter.toString(36) + Math.floor(Math.random() * 46656).toString(36)
}

function cleanText(value) {
  var text = String(value === undefined || value === null ? "" : value)
  text = text.replace(/\s+/g, " ").replace(/^ +| +$/g, "")
  return text.length > MAX_TEXT ? text.slice(0, MAX_TEXT) : text
}

function isDayKey(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(value))
}

function dayKey(date) {
  return date.getFullYear() + "-" + pad2(date.getMonth() + 1) + "-" + pad2(date.getDate())
}

function keyToDate(key) {
  var parts = String(key).split("-")
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
}

function shiftKey(key, deltaDays) {
  var date = keyToDate(key)
  date.setDate(date.getDate() + deltaDays)
  return dayKey(date)
}

// ------------------------------------------------------------------ parsing

function emptyDay(key) {
  return { date: String(key), big3: [], todos: [] }
}

function emptyState() {
  return { version: VERSION, days: {} }
}

function sanitizeItem(value) {
  if (!value || typeof value !== "object") return null
  var text = cleanText(value.text)
  if (text.length === 0) return null

  var done = value.done === true
  return {
    id: value.id ? String(value.id) : newId(),
    text: text,
    done: done,
    createdAt: value.createdAt ? String(value.createdAt) : "",
    completedAt: done && value.completedAt ? String(value.completedAt) : "",
    firstSeen: value.firstSeen ? String(value.firstSeen) : "",
    carriedFrom: value.carriedFrom ? String(value.carriedFrom) : "",
    carries: Math.max(0, Math.round(Number(value.carries) || 0))
  }
}

function sanitizeList(value, limit) {
  var out = []
  if (!value || value.length === undefined) return out
  for (var i = 0; i < value.length && out.length < limit; i++) {
    var item = sanitizeItem(value[i])
    if (item) out.push(item)
  }
  return out
}

function sanitizeDay(value, key) {
  var raw = value && typeof value === "object" ? value : {}
  return {
    date: String(key),
    big3: sanitizeList(raw.big3, BIG3_SLOTS),
    todos: sanitizeList(raw.todos, MAX_TODOS)
  }
}

// A malformed or missing file is not an error worth surfacing — it is just an
// empty history. Losing a corrupt file's contents beats refusing to run.
function parseState(raw) {
  var state = emptyState()
  if (!raw) return state

  var parsed = null
  try {
    parsed = JSON.parse(raw)
  } catch (e) {
    return state
  }
  if (!parsed || typeof parsed !== "object") return state

  var days = parsed.days && typeof parsed.days === "object" ? parsed.days : {}
  for (var key in days) {
    if (!isDayKey(key)) continue
    state.days[key] = sanitizeDay(days[key], key)
  }
  return state
}

function dayCount(state) {
  var n = 0
  for (var key in (state || {}).days || {}) n++
  return n
}

// Read a history file, separating "there is nothing here yet" from "this did
// not parse". The caller needs the difference: an empty read on first run is
// a legitimate empty history, but an empty or unparseable read *after* we have
// data means someone truncated the file under us — a torn external write, a
// half-flushed editor — and adopting it would hand back an empty day that we
// would then persist over the real one.
function readState(raw) {
  var text = raw === undefined || raw === null ? "" : String(raw)
  if (text.replace(/^\s+|\s+$/g, "").length === 0)
    return { state: emptyState(), ok: true, empty: true }

  var parsed = null
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return { state: emptyState(), ok: false, empty: false }
  }
  if (!parsed || typeof parsed !== "object")
    return { state: emptyState(), ok: false, empty: false }

  var state = parseState(text)
  return { state: state, ok: true, empty: dayCount(state) === 0 }
}

function serializeState(state) {
  return JSON.stringify({ version: VERSION, days: (state || emptyState()).days }, null, 2) + "\n"
}

// --------------------------------------------------------- state transitions
//
// Every mutation returns a *new* top-level state object. QML only re-evaluates
// bindings when the property's value changes, and an in-place edit of the same
// object is invisible to it, so identity has to change on every write.

function cloneItem(item) {
  return {
    id: item.id,
    text: item.text,
    done: item.done,
    createdAt: item.createdAt,
    completedAt: item.completedAt,
    firstSeen: item.firstSeen,
    carriedFrom: item.carriedFrom,
    carries: item.carries
  }
}

function cloneDay(day) {
  var out = emptyDay(day.date)
  for (var i = 0; i < day.big3.length; i++) out.big3.push(cloneItem(day.big3[i]))
  for (var j = 0; j < day.todos.length; j++) out.todos.push(cloneItem(day.todos[j]))
  return out
}

function withDay(state, key, day) {
  var days = {}
  for (var k in state.days) days[k] = state.days[k]
  days[key] = day
  return { version: VERSION, days: days }
}

function dayOf(state, key) {
  return state.days[key] || emptyDay(key)
}

function sortedKeys(state) {
  var keys = []
  for (var key in state.days) keys.push(key)
  keys.sort()
  return keys
}

function latestKeyBefore(state, key) {
  var keys = sortedKeys(state)
  var best = ""
  for (var i = 0; i < keys.length; i++) {
    if (keys[i] < key) best = keys[i]
    else break
  }
  return best
}

// An unfinished item follows you into the next day. `carries` is how many
// mornings it has survived, which the panel surfaces so a task that keeps
// sliding becomes visible rather than quietly accumulating.
function carryForward(item, fromKey) {
  var copy = cloneItem(item)
  copy.done = false
  copy.completedAt = ""
  copy.firstSeen = item.firstSeen || item.carriedFrom || fromKey
  copy.carriedFrom = fromKey
  copy.carries = (Number(item.carries) || 0) + 1
  return copy
}

// Build today from the most recent day on record — not necessarily yesterday,
// since the machine may have been off. Unfinished Big 3 items come across as
// regular todos: they had their shot at being one of the three, and today's
// three are chosen fresh.
function rollForward(state, key) {
  if (state.days[key]) return { state: state, created: false, carried: 0 }

  var day = emptyDay(key)
  var previousKey = latestKeyBefore(state, key)
  var carried = 0

  if (previousKey) {
    var previous = state.days[previousKey]
    var i
    for (i = 0; i < previous.big3.length; i++) {
      if (previous.big3[i].done) continue
      if (day.todos.length >= MAX_TODOS) break
      day.todos.push(carryForward(previous.big3[i], previousKey))
      carried++
    }
    for (i = 0; i < previous.todos.length; i++) {
      if (previous.todos[i].done) continue
      if (day.todos.length >= MAX_TODOS) break
      day.todos.push(carryForward(previous.todos[i], previousKey))
      carried++
    }
  }

  return { state: prune(withDay(state, key, day)), created: true, carried: carried }
}

function prune(state) {
  var keys = sortedKeys(state)
  if (keys.length <= HISTORY_DAYS) return state

  var keep = keys.slice(keys.length - HISTORY_DAYS)
  var days = {}
  for (var i = 0; i < keep.length; i++) days[keep[i]] = state.days[keep[i]]
  return { version: VERSION, days: days }
}

function listOf(day, kind) {
  return kind === "big3" ? day.big3 : day.todos
}

function setList(day, kind, list) {
  if (kind === "big3") day.big3 = list
  else day.todos = list
  return day
}

function addItem(state, key, kind, text, nowIso) {
  var clean = cleanText(text)
  if (clean.length === 0) return state

  var day = cloneDay(dayOf(state, key))
  var list = listOf(day, kind)
  var limit = kind === "big3" ? BIG3_SLOTS : MAX_TODOS
  if (list.length >= limit) return state

  list.push({
    id: newId(),
    text: clean,
    done: false,
    createdAt: String(nowIso || ""),
    completedAt: "",
    firstSeen: key,
    carriedFrom: "",
    carries: 0
  })
  return withDay(state, key, day)
}

function toggleItem(state, key, kind, id, nowIso) {
  var day = cloneDay(dayOf(state, key))
  var list = listOf(day, kind)
  for (var i = 0; i < list.length; i++) {
    if (list[i].id !== id) continue
    list[i].done = !list[i].done
    list[i].completedAt = list[i].done ? String(nowIso || "") : ""
    return withDay(state, key, day)
  }
  return state
}

function removeItem(state, key, kind, id) {
  var day = cloneDay(dayOf(state, key))
  var list = listOf(day, kind)
  var next = []
  for (var i = 0; i < list.length; i++) if (list[i].id !== id) next.push(list[i])
  if (next.length === list.length) return state
  return withDay(state, key, setList(day, kind, next))
}

function renameItem(state, key, kind, id, text) {
  var clean = cleanText(text)
  if (clean.length === 0) return removeItem(state, key, kind, id)

  var day = cloneDay(dayOf(state, key))
  var list = listOf(day, kind)
  for (var i = 0; i < list.length; i++) {
    if (list[i].id !== id) continue
    if (list[i].text === clean) return state
    list[i].text = clean
    return withDay(state, key, day)
  }
  return state
}

// Move an item between the Big 3 and the regular list. Promotion is refused
// when the three slots are taken — the cap is the whole point of the section.
function moveItem(state, key, fromKind, id) {
  var toKind = fromKind === "big3" ? "todos" : "big3"
  var day = cloneDay(dayOf(state, key))
  var from = listOf(day, fromKind)
  var to = listOf(day, toKind)
  if (toKind === "big3" && to.length >= BIG3_SLOTS) return state

  for (var i = 0; i < from.length; i++) {
    if (from[i].id !== id) continue
    var item = from[i]
    from.splice(i, 1)
    to.push(item)
    return withDay(state, key, day)
  }
  return state
}

function reorderItem(state, key, kind, id, delta) {
  var day = cloneDay(dayOf(state, key))
  var list = listOf(day, kind)
  for (var i = 0; i < list.length; i++) {
    if (list[i].id !== id) continue
    var target = i + delta
    if (target < 0 || target >= list.length) return state
    var item = list[i]
    list[i] = list[target]
    list[target] = item
    return withDay(state, key, day)
  }
  return state
}

function clearCompleted(state, key) {
  var day = cloneDay(dayOf(state, key))
  var kept = []
  for (var i = 0; i < day.todos.length; i++) if (!day.todos[i].done) kept.push(day.todos[i])
  if (kept.length === day.todos.length) return state
  day.todos = kept
  return withDay(state, key, day)
}

// ----------------------------------------------------------------- measuring

function countDone(list) {
  var n = 0
  for (var i = 0; i < list.length; i++) if (list[i].done) n++
  return n
}

function dayStats(day) {
  var source = day || emptyDay("")
  var big3Done = countDone(source.big3)
  var todoDone = countDone(source.todos)
  var total = source.big3.length + source.todos.length
  var done = big3Done + todoDone
  var weightedTotal = source.big3.length * BIG3_WEIGHT + source.todos.length
  var weightedDone = big3Done * BIG3_WEIGHT + todoDone

  return {
    big3Total: source.big3.length,
    big3Done: big3Done,
    todoTotal: source.todos.length,
    todoDone: todoDone,
    total: total,
    done: done,
    remaining: total - done,
    ratio: total > 0 ? done / total : 0,
    weightedRatio: weightedTotal > 0 ? weightedDone / weightedTotal : 0,
    allDone: total > 0 && done === total
  }
}

// How far through the *working* window the clock is. Progress is judged
// against this rather than against midnight-to-midnight, because nobody is
// behind schedule at 6am and everybody is out of road at 11pm.
function dayFraction(date, startHour, endHour) {
  var start = Number(startHour)
  var end = Number(endHour)
  if (!isFinite(start)) start = 8
  if (!isFinite(end)) end = 22
  if (end <= start) end = start + 1

  var hours = date.getHours() + date.getMinutes() / 60
  return clamp01((hours - start) / (end - start))
}

// ------------------------------------------------------------------- moods
//
// The mascot's face is data, not a sprite sheet: each mood carries the curve
// of the mouth, the shape of the eyes, the brow tilt, and how many sweat drops
// to draw. Mascot.qml just paints what it is handed.

var MOODS = {
  empty: {
    key: "empty",
    label: "Idle",
    smile: 0.2, eyes: "flat", brow: 0, sweat: 0, sparkle: 0, wavy: false, urgency: 0
  },
  done: {
    key: "done",
    label: "Relaxed",
    smile: 1, eyes: "happy", brow: -0.2, sweat: 0, sparkle: 2, wavy: false, urgency: 0
  },
  easy: {
    key: "easy",
    label: "Easy",
    smile: 0.8, eyes: "happy", brow: 0, sweat: 0, sparkle: 0, wavy: false, urgency: 0.1
  },
  focused: {
    key: "focused",
    label: "Focused",
    smile: 0.3, eyes: "open", brow: 0.2, sweat: 0, sparkle: 0, wavy: false, urgency: 0.3
  },
  worried: {
    key: "worried",
    label: "Worried",
    smile: -0.4, eyes: "open", brow: 0.65, sweat: 1, sparkle: 0, wavy: false, urgency: 0.62
  },
  stressed: {
    key: "stressed",
    label: "Stressed",
    smile: -0.9, eyes: "wide", brow: 1, sweat: 2, sparkle: 0, wavy: true, urgency: 1
  }
}

// Two lines per mood, picked by the hour so the panel does not flicker between
// them every time a binding re-evaluates.
var TAGLINES = {
  empty: ["Nothing planned yet.", "Give the day a shape."],
  done: ["All clear. Go enjoy it.", "Done and dusted."],
  easy: ["Comfortably ahead.", "This is going well."],
  focused: ["On pace. Keep going.", "Steady as she goes."],
  worried: ["The day is getting on.", "Slipping behind a little."],
  stressed: ["A lot of day has gone.", "Pick one and start it."]
}

function moodKey(stats, dayFrac) {
  if (stats.total === 0) return "empty"
  if (stats.allDone) return "done"

  var deficit = clamp01(dayFrac - stats.weightedRatio)
  if (deficit < 0.15) return "easy"
  if (deficit < 0.35) return "focused"
  if (deficit < 0.6) return "worried"
  return "stressed"
}

function moodFor(stats, dayFrac, hour) {
  var key = moodKey(stats, dayFrac)
  var base = MOODS[key]
  var deficit = stats.total === 0 ? 0 : clamp01(dayFrac - stats.weightedRatio)
  var lines = TAGLINES[key]

  return {
    key: base.key,
    label: base.label,
    tagline: lines[Math.abs(Math.round(Number(hour) || 0)) % lines.length],
    smile: base.smile,
    eyes: base.eyes,
    brow: base.brow,
    sweat: base.sweat,
    sparkle: base.sparkle,
    wavy: base.wavy,
    // 0 = calm, 1 = out of time. Drives the mascot's color and its fidget.
    urgency: key === "done" || key === "empty" ? 0 : Math.max(base.urgency * 0.5, deficit),
    deficit: deficit
  }
}

// ------------------------------------------------------------------ history

function historySeries(state, endKey, count) {
  var out = []
  var key = endKey
  for (var i = 0; i < count; i++) {
    var day = state.days[key]
    var stats = dayStats(day || emptyDay(key))
    out.unshift({ key: key, stats: stats, tracked: !!day && stats.total > 0 })
    key = shiftKey(key, -1)
  }
  return out
}

// Consecutive days, walking back from today, where everything planned got
// done. Today only counts once it is actually clear, so the streak never
// claims a day that is still in progress.
function streak(state, endKey) {
  var count = 0
  var key = endKey
  for (var guard = 0; guard < HISTORY_DAYS; guard++) {
    var day = state.days[key]
    if (!day) break
    var stats = dayStats(day)
    if (!stats.allDone) break
    count++
    key = shiftKey(key, -1)
  }
  return count
}

function totals(state) {
  var keys = sortedKeys(state)
  var completed = 0
  var planned = 0
  for (var i = 0; i < keys.length; i++) {
    var stats = dayStats(state.days[keys[i]])
    completed += stats.done
    planned += stats.total
  }
  return { completed: completed, planned: planned, days: keys.length }
}
