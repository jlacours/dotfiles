pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  readonly property string scriptPath:
    Quickshell.env("HOME") + "/.config/quickshell/scripts/audio-rate.sh"
  readonly property var rates: [0, 44100, 48000, 96000, 192000]

  property bool ok: false
  property int graphRate: 0
  property int forcedRate: 0
  property bool panelVisible: false
  property string panelScreenName: ""

  function formatRate(rate) {
    if (!rate) return "AUTO"
    if (rate === 44100) return "44.1"
    return String(Math.round(rate / 1000))
  }

  function toggle(screenName) {
    const target = screenName || ""
    if (panelVisible && panelScreenName === target) {
      panelVisible = false
      return
    }
    panelScreenName = target
    panelVisible = true
    refresh()
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function selectRate(rate) {
    if (setProc.running) return
    setProc.command = [root.scriptPath, "set", String(rate)]
    setProc.running = true
  }

  function parse(text, announce) {
    if (!text || !text.trim()) return
    try {
      const data = JSON.parse(text)
      ok = Boolean(data.ok)
      graphRate = Number(data.graphRate || 0)
      forcedRate = Number(data.forcedRate || 0)
      if (announce && ok) {
        OsdState.show("󰎈", forcedRate === 0
          ? "AUDIO RATE AUTO · " + formatRate(graphRate) + " KHZ"
          : "AUDIO RATE " + formatRate(forcedRate) + " KHZ")
      }
    } catch (e) {
      console.warn("AudioRateState: failed to parse status:", e)
    }
  }

  Component.onCompleted: refresh()

  Timer {
    interval: root.panelVisible ? 2000 : 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: [root.scriptPath, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text, false)
    }
  }

  Process {
    id: setProc
    command: [root.scriptPath, "set", "0"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text, true)
    }
  }

  IpcHandler {
    target: "audiorate"
    function toggle(screen: string): void { root.toggle(screen) }
    function open(screen: string): void {
      root.panelScreenName = screen
      root.panelVisible = true
      root.refresh()
    }
    function hide(): void { root.panelVisible = false }
    function set(rate: int): void { root.selectRate(rate) }
    function poll(): void { root.refresh() }
  }
}
