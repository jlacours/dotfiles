pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Tracks the CPU scaling governor (intel_pstate: performance | powersave) and
// toggles it via pkexec. Kept generic (setGovernor/toggle) so power-profile
// tooling can build on top of it.
Singleton {
  id: root

  readonly property string sysfsPath: "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
  property string governor: ""
  readonly property bool performance: governor === "performance"

  function refresh() {
    if (readProc.running) return
    readProc.exec(["cat", root.sysfsPath])
  }

  function setGovernor(name) {
    if (toggleProc.running) return
    toggleProc.exec(["pkexec", "sh", "-c",
      "echo " + name + " | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor"])
  }

  function toggle() {
    root.setGovernor(root.performance ? "powersave" : "performance")
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: readProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text) root.governor = text.trim()
      }
    }
  }

  // Re-read after a toggle lands so the label reflects the new mode.
  Process {
    id: toggleProc
    onExited: root.refresh()
  }
}
