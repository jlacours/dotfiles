import QtQuick
import QtQuick.Effects

// Notification "matrix" rain: on a notification the whole bar background fills
// with vertical katakana digital-rain for a few seconds, then fades.  Columns
// drop top-to-bottom at varied speeds, each with a bright bold leading head and
// a fading trail.  Rendered as real Text items (Canvas fillText is unreliable
// here), behind the modules, with a bloom layer for glow.  Call play().
Item {
  id: root

  property color glyphColor: Theme.accent
  property int duration: 5200  // how long the rain lasts
  property int loops: 4        // full drops per column over the run
  property real fall: 0        // 0..1 master fall progress
  property real intensity: 0   // overall fade in/out
  property bool playing: false
  property int tick: 0         // bumped on a timer to flicker the glyphs

  readonly property int trailLen: 3
  readonly property int columnCount: Math.max(8, Math.min(60, Math.floor(width / 24)))
  readonly property int glyphCount: columnCount * trailLen
  readonly property int fontPx: Math.max(6, Math.round(height * 0.78))
  readonly property real step: fontPx * 0.9

  // Half-width katakana (+ a few digits) — the classic Matrix glyph set.
  // Requires a font with katakana coverage (Code2000, below).
  readonly property string glyphs: "ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789"

  // Deterministic pseudo-random glyph, stable until `tick` changes (flicker).
  function glyphAt(seed) {
    const s = Math.abs(Math.sin((seed + 1) * (root.tick + 1) * 12.9898) * 43758.5453)
    return glyphs.charAt(Math.floor((s - Math.floor(s)) * glyphs.length))
  }

  // Stable per-column/glyph random in [0,1) — independent of tick.
  function rnd(i, salt) {
    const s = Math.abs(Math.sin((i + 1) * salt) * 7561.317)
    return s - Math.floor(s)
  }

  function colOf(i)  { return Math.floor(i / root.trailLen) }
  function tOf(i)    { return i % root.trailLen }

  function slotX(i) {
    return (colOf(i) + 0.5) * (root.width / root.columnCount)
  }

  // Vertical position: each column's head wraps down its cycle; trail sits above.
  function slotY(i) {
    const fl = root.fall, playing = root.playing, t = root.tick
    const col = colOf(i)
    const cycle = root.height + root.trailLen * root.step
    const speed = 0.6 + rnd(col, 91.7) * 0.9
    const phase = rnd(col, 13.3)
    const pos = (phase + fl * root.loops * speed) % 1
    return pos * cycle - tOf(i) * root.step
  }

  // Brightest at the head, fading up the trail, soft at the top/bottom edges.
  function glyphOpacity(i) {
    const inten = root.intensity, fl = root.fall, playing = root.playing
    if (!playing) return 0
    const trail = 1 - tOf(i) / root.trailLen
    const dim = 0.55 + 0.45 * rnd(colOf(i), 22.3)
    const y = slotY(i)
    const vEdge = Math.max(0, Math.min(1, Math.min(y, root.height - y) / 5 + 0.15))
    return trail * dim * inten * vEdge
  }

  // Heads run hot (toward white) so the bloom makes them glow.
  function slotColor(i) {
    const c = root.glyphColor
    let k = 0
    if (tOf(i) === 0) k = 0.7
    else if (tOf(i) === 1) k = 0.18
    if (k === 0) return c
    return Qt.rgba(c.r + (1 - c.r) * k, c.g + (1 - c.g) * k, c.b + (1 - c.b) * k, 1)
  }

  // Sharp glyph field (also the bloom source).
  Item {
    id: field
    anchors.fill: parent
    layer.enabled: true

    Repeater {
      model: root.glyphCount

      Text {
        required property int index

        font.family: "Code2000"
        font.pixelSize: root.fontPx
        color: root.slotColor(index)
        text: root.glyphAt(index)
        opacity: root.glyphOpacity(index)
        visible: opacity > 0.01
        x: Math.round(root.slotX(index) - width / 2)
        y: Math.round(root.slotY(index) - height / 2)
      }
    }
  }

  // Glow: a blurred, brightened copy of the field rendered behind the sharp one.
  MultiEffect {
    source: field
    anchors.fill: field
    z: -1
    blurEnabled: true
    blur: 0.7
    blurMax: 18
    brightness: 0.12
    autoPaddingEnabled: true
  }

  // Flicker the glyphs while the rain is active.
  Timer {
    interval: 110
    repeat: true
    running: root.playing
    onTriggered: root.tick++
  }

  SequentialAnimation {
    id: seq
    running: false

    ParallelAnimation {
      // Constant-velocity fall for the whole run.
      NumberAnimation {
        target: root; property: "fall"
        from: 0; to: 1; duration: root.duration
        easing.type: Easing.Linear
      }
      // Hold full, then fade the rain out over the last stretch.
      SequentialAnimation {
        PauseAnimation { duration: Math.max(0, root.duration - 1100) }
        NumberAnimation {
          target: root; property: "intensity"
          to: 0; duration: 1100
          easing.type: Easing.InQuad
        }
      }
    }
    ScriptAction { script: root.playing = false }
  }

  function play() {
    seq.stop()
    root.fall = 0
    root.intensity = 1
    root.playing = true
    seq.restart()
  }
}
