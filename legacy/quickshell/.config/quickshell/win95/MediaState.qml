pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Small, player-agnostic MPRIS bridge for the taskbar. playerctl's default
// target is the most recently active player, which keeps the control useful
// for TIDAL, browsers, MPD, and whatever else registers a media session.
Singleton {
  id: root

  property bool available: false
  property bool playing: false
  property bool sawStatus: false

  function refresh(): void {
    sawStatus = false;
    statusProc.running = true;
  }

  function toggle(): void {
    toggleProc.running = true;
  }

  Process {
    id: statusProc
    command: ["playerctl", "status"]
    running: true
    stdout: SplitParser {
      onRead: (line) => {
        const status = line.trim();
        root.sawStatus = status === "Playing" || status === "Paused" || status === "Stopped";
        root.available = root.sawStatus;
        root.playing = status === "Playing";
      }
    }
    onExited: {
      if (!root.sawStatus) {
        root.available = false;
        root.playing = false;
      }
    }
  }

  Process {
    id: toggleProc
    command: ["playerctl", "play-pause"]
    onExited: root.refresh()
  }

  // MPRIS has no shared Quickshell service here; a light poll keeps the icon
  // in sync with keyboard media keys and players opened outside the shell.
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
}
