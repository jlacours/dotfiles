pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Keep-awake backing state. Reuses the shared idle-inhibit.sh helper, which
// parks wayland-idle-inhibitor.py on a zwp_idle_inhibit lock — honored by
// Labwc, so hypridle's 15-minute monitor-off rule never fires while held.
Singleton {
  id: root

  property bool inhibited: false

  readonly property string helper:
    Quickshell.env("HOME") + "/.config/quickshell/scripts/idle-inhibit.sh"

  function toggle(): void {
    // Optimistic flip for immediate feedback; refresh() confirms on exit.
    inhibited = !inhibited;
    toggleProc.running = true;
  }

  function refresh(): void {
    statusProc.running = true;
  }

  Process {
    id: toggleProc
    command: [root.helper, "toggle"]
    onExited: root.refresh()
  }

  Process {
    id: statusProc
    command: [root.helper, "status"]
    running: true
    stdout: SplitParser {
      onRead: (line) => {
        try {
          root.inhibited = JSON.parse(line)["class"] === "activated";
        } catch (e) {}
      }
    }
  }

  // The helper's pidfile can change behind our back (CLI use, inhibitor
  // death); a slow poll keeps the chip honest at negligible cost.
  Timer {
    interval: 15000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
}
