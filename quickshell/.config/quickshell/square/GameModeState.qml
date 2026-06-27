pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateFile: home + "/.local/state/game-mode/state.json"
  readonly property string scriptPath: home + "/.config/hypr/scripts/game-mode.sh"

  property bool active: false

  function refresh() {
    if (readProc.running) return
    readProc.exec(["cat", root.stateFile])
  }

  function toggle() {
    if (toggleProc.running) return
    toggleProc.exec([root.scriptPath, "toggle"])
  }

  Component.onCompleted: refresh()

  FileView {
    path: root.stateFile
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Process {
    id: readProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || !text.trim()) {
          root.active = false
          return
        }
        try {
          const data = JSON.parse(text)
          root.active = !!data.active
        } catch (e) {
          console.warn("GameModeState: failed to parse state:", e)
          root.active = false
        }
      }
    }
  }

  Process {
    id: toggleProc
    onExited: root.refresh()
  }

  // Fallback poll: catches keybind-driven toggles in case the FileView misses
  // the state file's first creation (inotify can't watch a not-yet-existing
  // path). Mirrors the safety timer in MicState.
  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }
}
