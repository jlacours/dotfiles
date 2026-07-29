pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string scriptPath: home + "/.config/quickshell/scripts/expressvpn.sh"

  property string state: "Unavailable"
  property string location: ""
  property string shortLocation: ""
  property string tooltip: "ExpressVPN unavailable"
  readonly property bool connected: root.state === "Connected"

  function refresh() {
    if (!statusProc.running) statusProc.exec([root.scriptPath, "status"])
  }

  function toggle() {
    if (!toggleProc.running) toggleProc.exec([root.scriptPath, "toggle"])
  }

  function parse(text) {
    if (!text || !text.trim()) return
    try {
      const data = JSON.parse(text)
      root.state = data.state || "Unavailable"
      root.location = data.location || ""
      root.shortLocation = data.short || ""
      root.tooltip = data.tooltip || "ExpressVPN unavailable"
    } catch (e) {
      root.state = "Unavailable"
      root.location = ""
      root.shortLocation = ""
      root.tooltip = "ExpressVPN status error"
    }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
  }

  Process {
    id: toggleProc
    onExited: refreshDelay.restart()
  }

  Timer {
    id: refreshDelay
    interval: 750
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
