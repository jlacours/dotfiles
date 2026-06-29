pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Visibility for the square bar's three center modules, shared across every
// monitor (singleton => one instance per engine, no cross-Variants sync).
// Persisted to ~/.local/state/quickshell/center-modules.json so the chosen
// layout survives quickshell reloads and relogins. Defaults to all-shown.
Singleton {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateDir: home + "/.local/state/quickshell"
  readonly property string stateFile: stateDir + "/center-modules.json"

  property bool aiUsage: true
  property bool tmux: true
  property bool vitals: true

  function readKey(obj, key) {
    const v = obj[key]
    return v === undefined ? true : !!v
  }

  function applyJson(text) {
    if (!text || !text.trim()) return
    try {
      const data = JSON.parse(text)
      root.aiUsage = root.readKey(data, "aiUsage")
      root.tmux = root.readKey(data, "tmux")
      root.vitals = root.readKey(data, "vitals")
    } catch (e) {
      console.warn("CenterModulesState: failed to parse state:", e)
    }
  }

  function save() {
    const json = JSON.stringify({
      aiUsage: root.aiUsage,
      tmux: root.tmux,
      vitals: root.vitals
    })
    // mkdir -p then write atomically enough for a tiny toggle file. $1=dir,
    // $2=json, $3=path ($0 is the throwaway "sh" slot for `sh -c`).
    writeProc.exec([
      "sh", "-c",
      'mkdir -p "$1" && printf "%s" "$2" > "$3"',
      "_", root.stateDir, json, root.stateFile
    ])
  }

  function toggle(key) {
    if (key === "aiUsage") root.aiUsage = !root.aiUsage
    else if (key === "tmux") root.tmux = !root.tmux
    else if (key === "vitals") root.vitals = !root.vitals
    root.save()
  }

  Component.onCompleted: readProc.exec(["cat", root.stateFile])

  Process {
    id: readProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyJson(text)
    }
    // cat exits non-zero on first run (no file yet) -- defaults stay put.
  }

  Process {
    id: writeProc
  }
}
