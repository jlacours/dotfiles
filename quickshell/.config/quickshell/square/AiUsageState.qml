pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Aggregated usage for the three AI subscriptions (Claude, ChatGPT/Codex, z.ai).
// Backed by scripts/ai-usage.sh, which emits a single JSON blob. Also owns the
// expand-panel open/close state, mirroring NotificationState's pattern.
Singleton {
  id: root

  readonly property string scriptPath:
    Quickshell.env("HOME") + "/.config/quickshell/scripts/ai-usage.sh"

  // Parsed payload + per-provider convenience accessors (always defined).
  property var data: ({ claude: { ok: false }, codex: { ok: false }, zai: { ok: false }, openrouter: { ok: false } })
  readonly property var claude:     (data && data.claude)     ? data.claude     : ({ ok: false })
  readonly property var codex:      (data && data.codex)      ? data.codex      : ({ ok: false })
  readonly property var zai:        (data && data.zai)        ? data.zai        : ({ ok: false })
  readonly property var openrouter: (data && data.openrouter) ? data.openrouter : ({ ok: false })
  property bool ready: false

  // Expand-panel state.
  property bool panelVisible: false
  property string panelScreenName: ""
  property string selected: "claude"   // claude | codex | zai

  // Ticking clock (ms) so "resets in" countdowns stay live while the panel is open.
  property double now: Date.now()

  function toggle(provider, screenName) {
    const target = screenName || ""
    if (panelVisible && selected === provider && panelScreenName === target) {
      panelVisible = false
      return
    }
    selected = provider
    panelScreenName = target
    panelVisible = true
    refresh()
  }

  function close() {
    panelVisible = false
  }

  function refresh() {
    if (!proc.running) proc.running = true
  }

  function parse(text) {
    if (!text || !text.trim()) return
    try {
      data = JSON.parse(text)
      ready = true
    } catch (e) {
      console.warn("AiUsageState: failed to parse usage JSON:", e)
    }
  }

  // ── formatting helpers (shared by the bar block and the panel) ──
  function fmtTokens(t) {
    if (t === undefined || t === null || t < 0) return "--"
    if (t >= 1e6) return (t / 1e6).toFixed(1) + "M"
    if (t >= 1e3) return Math.round(t / 1e3) + "K"
    return String(t)
  }

  function fmtDur(sec) {
    if (sec === null || sec === undefined || isNaN(sec)) return "--"
    if (sec < 0) sec = 0
    const d = Math.floor(sec / 86400)
    const h = Math.floor((sec % 86400) / 3600)
    const m = Math.floor((sec % 3600) / 60)
    if (d > 0) return d + "d " + h + "h"
    if (h > 0) return h + "h " + m + "m"
    return m + "m"
  }

  // epoch seconds in the future → "2h 14m"
  function resetIn(epochSec) {
    if (!epochSec) return "--"
    return fmtDur(epochSec - Math.floor(now / 1000))
  }

  // epoch seconds in the past → "12m ago"
  function ago(epochSec) {
    if (!epochSec) return ""
    return fmtDur(Math.floor(now / 1000) - epochSec) + " ago"
  }

  Component.onCompleted: refresh()

  // Usage windows move slowly; a one-minute poll is plenty (and ccusage ~2s).
  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // Keep countdowns live only while the panel is on screen.
  Timer {
    interval: 1000
    running: root.panelVisible
    repeat: true
    triggeredOnStart: true
    onTriggered: root.now = Date.now()
  }

  Process {
    id: proc
    command: [root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
  }

  // Lets a Hyprland keybind drive the panel, e.g.
  //   qs-ipc.sh aiusage toggle claude <monitor>
  IpcHandler {
    target: "aiusage"
    function toggle(provider: string, screen: string): void { root.toggle(provider, screen) }
    function open(provider: string, screen: string): void {
      root.selected = provider
      root.panelScreenName = screen
      root.panelVisible = true
      root.refresh()
    }
    function hide(): void { root.close() }
    function poll(): void { root.refresh() }
  }
}
