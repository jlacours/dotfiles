import Quickshell
import Quickshell.Io
import QtQuick 6.4

// Two mirrored oscilloscopes growing out of the center. cava's speech bands
// drive four harmonics of one continuous wave, so the trace stays smooth; each
// harmonic rises fast and falls slowly. `feeding` runs cava (start it early so
// it is warm); `shown` fades the scopes in and out. A tesseract spins where the
// scopes meet. Hot data lives in plain JS arrays inside one object: reading a
// QML `var` array property copies it.
Item {
    id: root

    property color color: "white"
    property bool feeding: false
    property bool shown: false
    // The scope keeps its own height; the rest of the item is tesseract room.
    property real scopeHeight: 64

    readonly property var hot: ({
        freqs: [1.2, 2.1, 3.4, 5.3],      // cycles across one half
        speeds: [3.1, 4.7, 6.3, 8.9],     // rad/s, travelling outward
        gains: [1.0, 0.75, 0.55, 0.4],
        targets: [0, 0, 0, 0],
        energies: [0, 0, 0, 0],
        phase: 0,
        // Tesseract: 16 corners (±1, ±1, ±1, ±1) and 32 edges joining corners
        // that differ in one axis, as flat index pairs.
        verts: Array.from({ length: 16 }, (_, i) => [0, 1, 2, 3].map(b => (i >> b & 1) * 2 - 1)),
        edges: [].concat(...Array.from({ length: 64 }, (_, n) => [n >> 2, (n >> 2) ^ (1 << (n & 3))])
            .filter(([i, j]) => j > i)),
        // XW, YW, ZW, XY plane angles, one band each: low voice turns it
        // inside out through w, sibilants twist it flat.
        angles: [0, 0, 0, 0],
        spinBase: [0.22, 0.17, 0.13, 0.09],  // rad/s while silent
        spinGain: [2.4, 1.9, 1.6, 2.2]       // extra rad/s at full band energy
    })

    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on opacity {
        NumberAnimation { duration: 380; easing.type: Easing.InOutCubic }
    }

    onFeedingChanged: if (!feeding) hot.targets.fill(0)

    Process {
        running: root.feeding
        command: ["cava", "-p", (Quickshell.env("HOME") || "") + "/.config/quickshell/speakscope/cava.conf"]
        stdout: SplitParser {
            onRead: data => {
                // 24 bars -> 4 groups of 6, peak of each; a mild curve keeps loud/quiet contrast.
                const parts = data.split(";")
                const targets = root.hot.targets
                for (let k = 0; k < 4; k++) {
                    let peak = 0
                    for (let i = k * 6; i < k * 6 + 6; i++)
                        peak = Math.max(peak, parseInt(parts[i]) || 0)
                    targets[k] = Math.pow(Math.min(1, peak / 100), 0.75)
                }
            }
        }
    }

    FrameAnimation {
        running: root.visible
        onTriggered: {
            const s = root.hot
            const dt = Math.min(frameTime, 0.05)
            // Louder speech also makes the wave travel faster.
            const level = Math.max(s.energies[0], s.energies[1], s.energies[2], s.energies[3])
            s.phase += dt * (0.5 + 1.8 * level)
            const attack = 1 - Math.exp(-dt * 40)
            const release = 1 - Math.exp(-dt * 12)
            for (let k = 0; k < 4; k++) {
                const t = s.targets[k]
                const e = s.energies[k]
                s.energies[k] = e + (t - e) * (t > e ? attack : release)
                s.angles[k] = (s.angles[k] + dt * (s.spinBase[k] + s.spinGain[k] * s.energies[k])) % (2 * Math.PI)
            }
            scope.requestPaint()
        }
    }

    Canvas {
        id: scope
        anchors.fill: parent
        renderStrategy: Canvas.Threaded

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const s = root.hot
            const cx = width / 2
            const mid = height / 2
            const amp = root.scopeHeight * 0.46
            const level = Math.max(s.energies[0], s.energies[1], s.energies[2], s.energies[3])
            // Tesseract scale: its projection never exceeds 2.79 units (see
            // the perspective distances below), with room for the pulse.
            const unit = (height / 2 - 5) / 3.13 * (1 + 0.12 * level)
            const steps = 96
            // Per-frame harmonic amplitudes and phases, computed once.
            const a = [], w = [], p = []
            for (let k = 0; k < 4; k++) {
                a.push(1.25 * s.gains[k] * s.energies[k])
                w.push(2 * Math.PI * s.freqs[k])
                p.push(k * 1.7 - s.phase * s.speeds[k])
            }
            const ys = []
            for (let i = 0; i <= steps; i++) {
                const u = i / steps
                // Smoothed distance from the center (no corner at 0), and a
                // cosine taper that is flat there: the mirrored halves meet in
                // a round crest instead of a point.
                const d = Math.sqrt(u * u + 0.004) - 0.0632
                const y = a[0] * Math.sin(w[0] * d + p[0]) + a[1] * Math.sin(w[1] * d + p[1])
                    + a[2] * Math.sin(w[2] * d + p[2]) + a[3] * Math.sin(w[3] * d + p[3])
                const taper = Math.pow(Math.cos(Math.PI / 2 * u), 1.2)
                // tanh soft-limits: loud peaks get tall without clipping flat.
                ys.push(mid + amp * taper * Math.tanh(y))
            }
            // Same samples on both sides, mirrored around the center.
            ctx.beginPath()
            for (const side of [-1, 1]) {
                ctx.moveTo(cx, ys[0])
                for (let i = 1; i <= steps; i++)
                    ctx.lineTo(cx + side * (i / steps) * cx, ys[i])
            }
            const c = root.color
            // Fades out at both ends and dips inside the tesseract, so the
            // scopes read as wings coming off it.
            const hole = Math.min(0.45, unit * 3.2 / width)
            const fade = alpha => {
                const g = ctx.createLinearGradient(0, 0, width, 0)
                g.addColorStop(0, Qt.rgba(c.r, c.g, c.b, 0))
                g.addColorStop(0.5 - hole, Qt.rgba(c.r, c.g, c.b, alpha))
                g.addColorStop(0.5, Qt.rgba(c.r, c.g, c.b, alpha * 0.15))
                g.addColorStop(0.5 + hole, Qt.rgba(c.r, c.g, c.b, alpha))
                g.addColorStop(1, Qt.rgba(c.r, c.g, c.b, 0))
                return g
            }
            ctx.lineJoin = "round"
            ctx.lineCap = "round"
            // Soft glow underneath, then the crisp trace.
            ctx.strokeStyle = fade(0.22)
            ctx.lineWidth = 6
            ctx.stroke()
            ctx.strokeStyle = fade(1)
            ctx.lineWidth = 2
            ctx.stroke()

            // The tesseract where both scopes meet: spun in its four band
            // planes, then a slow 3D tumble and a fixed tilt, projected
            // 4D -> 3D -> 2D in perspective (distances 3.5 and 5).
            const cs = s.angles.map(Math.cos)
            const sn = s.angles.map(Math.sin)
            const ct = Math.cos(s.phase * 0.35)
            const st = Math.sin(s.phase * 0.35)
            const px = [], py = [], pw = []
            for (const v of s.verts) {
                let x = v[0], y = v[1], z = v[2], w = v[3], t
                t = x * cs[0] - w * sn[0]; w = x * sn[0] + w * cs[0]; x = t
                t = y * cs[1] - w * sn[1]; w = y * sn[1] + w * cs[1]; y = t
                t = z * cs[2] - w * sn[2]; w = z * sn[2] + w * cs[2]; z = t
                t = x * cs[3] - y * sn[3]; y = x * sn[3] + y * cs[3]; x = t
                t = x * ct - z * st; z = x * st + z * ct; x = t
                t = y * 0.921 - z * 0.389; z = y * 0.389 + z * 0.921; y = t
                const f = 3.5 / (3.5 - w)
                const g = unit * 5 / (5 - z * f)
                px.push(cx + x * f * g)
                py.push(mid + y * f * g)
                pw.push(w)
            }
            const tint = (shift, light, alpha) => Qt.hsla((c.hslHue + shift + 1) % 1,
                Math.min(1, c.hslSaturation + 0.1), Math.max(0, Math.min(0.85, c.hslLightness + light)), alpha)
            // Faint halo that swells with the voice.
            const halo = ctx.createRadialGradient(cx, mid, 0, cx, mid, unit * 2.4)
            halo.addColorStop(0, tint(0, 0.1, 0.1 + 0.25 * level))
            halo.addColorStop(1, tint(0, 0, 0))
            ctx.fillStyle = halo
            ctx.fillRect(cx - unit * 2.4, mid - unit * 2.4, unit * 4.8, unit * 4.8)
            // Depth cue by w: edges go into five buckets, far (inner cube,
            // hue-shifted, dim, thin) to near (accent, bright). Far buckets
            // first; one path and two strokes per bucket, not per edge.
            const bins = [[], [], [], [], []]
            const e = s.edges
            for (let n = 0; n < e.length; n += 2) {
                const depth = (pw[e[n]] + pw[e[n + 1]] + 4) / 8
                bins[Math.min(4, Math.floor(depth * 5))].push(e[n], e[n + 1])
            }
            for (let b = 0; b < 5; b++) {
                const list = bins[b]
                if (!list.length)
                    continue
                const d = (b + 0.5) / 5
                ctx.beginPath()
                for (let n = 0; n < list.length; n += 2) {
                    ctx.moveTo(px[list[n]], py[list[n]])
                    ctx.lineTo(px[list[n + 1]], py[list[n + 1]])
                }
                ctx.strokeStyle = tint(0.12 * (1 - d), 0.05, (0.06 + 0.16 * d) * (0.7 + 0.6 * level))
                ctx.lineWidth = 4 + 3 * d
                ctx.stroke()
                ctx.strokeStyle = tint(0.12 * (1 - d), 0.25 * d - 0.05, 0.3 + 0.7 * d)
                ctx.lineWidth = 0.8 + 1.4 * d
                ctx.stroke()
            }
        }
    }
}
