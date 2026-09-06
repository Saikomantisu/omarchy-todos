import QtQuick

// Pip — the little face that reacts to how the day is going.
//
// Drawn rather than shipped as an image so it inherits the theme's foreground
// and urgent colors, stays crisp at any size, and can be posed continuously:
// Model.js hands over a mouth curvature, an eye shape, a brow tilt, and a
// sweat-drop count, and this file just paints them. The same component is the
// ~22px bar icon and the panel hero.
//
// The head is a solid silhouette and the face is punched *out* of it with
// destination-out compositing. An outlined face with 1px strokes turns to mud
// at bar size; negative space stays readable all the way down.
Item {
  id: root

  // Pose, straight out of Model.moodFor().
  property real urgency: 0          // 0 calm .. 1 out of time
  property real smile: 0.5          // 1 grin .. -1 frown
  property string eyes: "open"      // flat | happy | open | wide
  property real brow: 0             // 0 flat .. 1 fully worried
  property int sweat: 0             // drops, 0-2
  property int sparkle: 0           // sparkles, 0-2
  property bool wavy: false         // squiggle mouth instead of a curve

  property color baseColor: "#cacccc"
  property color alertColor: "#a55555"
  property bool animated: true

  // Stress shifts the ink toward the theme's urgent color, so the mascot reads
  // at a glance even before you parse the face.
  readonly property color inkColor: Qt.tint(baseColor, Qt.rgba(alertColor.r, alertColor.g, alertColor.b, Math.min(0.9, urgency * 0.95)))

  property bool blinking: false

  // One string that changes whenever anything painted changes. Cheaper than a
  // dozen onXChanged handlers, and it can't miss a property.
  readonly property string paintKey: [
    urgency.toFixed(3), smile.toFixed(3), eyes, brow.toFixed(3),
    sweat, sparkle, wavy, blinking, String(inkColor)
  ].join("|")

  onPaintKeyChanged: canvas.requestPaint()

  implicitWidth: 22
  implicitHeight: 22

  // Blinking costs two repaints every few seconds and is most of what makes
  // the thing feel alive. Skipped when the eyes are already closed.
  Timer {
    id: blinkGap
    interval: 3500
    running: root.animated && root.visible && root.eyes !== "happy" && root.eyes !== "flat"
    repeat: true
    onTriggered: {
      root.blinking = true
      blinkHold.restart()
      interval = 2600 + Math.random() * 4200
    }
  }

  Timer {
    id: blinkHold
    interval: 120
    onTriggered: root.blinking = false
  }

  // A stressed Pip fidgets; a finished Pip breathes. Both are slow enough to
  // register as mood rather than motion in the corner of your eye.
  SequentialAnimation on rotation {
    running: root.animated && root.visible && root.urgency > 0.6
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation { from: 0; to: -3; duration: 130; easing.type: Easing.InOutSine }
    NumberAnimation { from: -3; to: 3; duration: 260; easing.type: Easing.InOutSine }
    NumberAnimation { from: 3; to: 0; duration: 130; easing.type: Easing.InOutSine }
    PauseAnimation { duration: 2400 }
  }

  SequentialAnimation on scale {
    running: root.animated && root.visible && root.sparkle > 0
    loops: Animation.Infinite
    alwaysRunToEnd: true
    NumberAnimation { from: 1.0; to: 1.05; duration: 1400; easing.type: Easing.InOutSine }
    NumberAnimation { from: 1.05; to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    renderStrategy: Canvas.Cooperative

    onPaint: {
      var ctx = getContext("2d")
      var s = Math.min(width, height)
      if (s <= 0) return

      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      ctx.translate((width - s) / 2, (height - s) / 2)
      ctx.lineCap = "round"
      ctx.lineJoin = "round"

      var ink = root.inkColor
      // Detail that turns to mud below these sizes is simply left out; the
      // silhouette, eyes, and mouth carry the mood on their own.
      var showBrows = s >= 17
      var showSweat = s >= 17

      function u(v) { return v * s }

      function roundRect(x, y, w, h, r) {
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.lineTo(x + w - r, y)
        ctx.quadraticCurveTo(x + w, y, x + w, y + r)
        ctx.lineTo(x + w, y + h - r)
        ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
        ctx.lineTo(x + r, y + h)
        ctx.quadraticCurveTo(x, y + h, x, y + h - r)
        ctx.lineTo(x, y + r)
        ctx.quadraticCurveTo(x, y, x + r, y)
        ctx.closePath()
      }

      // Teardrop: a disc with a point on top. Used as negative space on the
      // temple, which is where a sweat drop belongs.
      function teardrop(cx, cy, r) {
        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, Math.PI * 2)
        ctx.fill()
        ctx.beginPath()
        ctx.moveTo(cx - r * 0.62, cy - r * 0.78)
        ctx.lineTo(cx, cy - r * 2.3)
        ctx.lineTo(cx + r * 0.62, cy - r * 0.78)
        ctx.closePath()
        ctx.fill()
      }

      function star(cx, cy, r) {
        ctx.beginPath()
        ctx.moveTo(cx, cy - r)
        ctx.quadraticCurveTo(cx + r * 0.2, cy - r * 0.2, cx + r, cy)
        ctx.quadraticCurveTo(cx + r * 0.2, cy + r * 0.2, cx, cy + r)
        ctx.quadraticCurveTo(cx - r * 0.2, cy + r * 0.2, cx - r, cy)
        ctx.quadraticCurveTo(cx - r * 0.2, cy - r * 0.2, cx, cy - r)
        ctx.closePath()
        ctx.fill()
      }

      // ---- silhouette ----------------------------------------------------
      ctx.fillStyle = ink
      ctx.strokeStyle = ink

      roundRect(u(0.05), u(0.15), u(0.90), u(0.82), u(0.29))
      ctx.fill()

      if (root.sparkle >= 1) star(u(0.895), u(0.085), u(0.075))
      if (root.sparkle >= 2 && s >= 20) star(u(0.115), u(0.07), u(0.052))

      // ---- face, punched out of the silhouette ---------------------------
      ctx.globalCompositeOperation = "destination-out"
      ctx.fillStyle = "#000000"
      ctx.strokeStyle = "#000000"

      var eyeY = u(0.50)
      var eyeXs = [u(0.325), u(0.675)]
      var shape = root.blinking && root.eyes !== "happy" ? "flat" : root.eyes
      var stroke = Math.max(1, s * 0.085)

      for (var e = 0; e < 2; e++) {
        var ex = eyeXs[e]
        if (shape === "flat") {
          ctx.lineWidth = stroke
          ctx.beginPath()
          ctx.moveTo(ex - u(0.085), eyeY)
          ctx.lineTo(ex + u(0.085), eyeY)
          ctx.stroke()
        } else if (shape === "happy") {
          ctx.lineWidth = stroke
          ctx.beginPath()
          ctx.moveTo(ex - u(0.095), eyeY + u(0.04))
          ctx.quadraticCurveTo(ex, eyeY - u(0.115), ex + u(0.095), eyeY + u(0.04))
          ctx.stroke()
        } else if (shape === "wide") {
          ctx.beginPath()
          ctx.arc(ex, eyeY, u(0.115), 0, Math.PI * 2)
          ctx.fill()
        } else {
          ctx.beginPath()
          ctx.arc(ex, eyeY, u(0.09), 0, Math.PI * 2)
          ctx.fill()
        }
      }

      if (showBrows && root.brow > 0.05) {
        var browY = u(0.315)
        var lift = u(0.06) * root.brow
        var drop = u(0.04) * root.brow
        ctx.lineWidth = Math.max(1, s * 0.07)

        ctx.beginPath()
        ctx.moveTo(u(0.185), browY + drop)
        ctx.lineTo(u(0.425), browY - lift)
        ctx.stroke()

        ctx.beginPath()
        ctx.moveTo(u(0.815), browY + drop)
        ctx.lineTo(u(0.575), browY - lift)
        ctx.stroke()
      }

      var mouthY = u(0.745)
      var left = u(0.33)
      var right = u(0.67)
      ctx.lineWidth = stroke
      ctx.beginPath()

      if (root.wavy) {
        // A squiggle says "not coping" in a way no single curve does.
        var steps = 3
        var span = (right - left) / steps
        ctx.moveTo(left, mouthY)
        for (var i = 1; i <= steps; i++) {
          ctx.quadraticCurveTo(
            left + span * (i - 0.5),
            mouthY + (i % 2 === 0 ? u(0.06) : -u(0.06)),
            left + span * i,
            mouthY)
        }
      } else {
        ctx.moveTo(left, mouthY)
        ctx.quadraticCurveTo(u(0.5), mouthY + u(0.24) * root.smile, right, mouthY)
      }
      ctx.stroke()

      if (showSweat) {
        if (root.sweat >= 1) teardrop(u(0.845), u(0.305), u(0.05))
        if (root.sweat >= 2) teardrop(u(0.155), u(0.275), u(0.044))
      }

      // A wide eye needs its pupil back, or alarm reads as two blank holes.
      ctx.globalCompositeOperation = "source-over"
      if (shape === "wide") {
        ctx.fillStyle = ink
        for (var p = 0; p < 2; p++) {
          ctx.beginPath()
          ctx.arc(eyeXs[p], eyeY + u(0.012), u(0.045), 0, Math.PI * 2)
          ctx.fill()
        }
      }
    }
  }
}
