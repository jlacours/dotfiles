pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
  id: root

  property bool dark: false

  readonly property color desktop: dark ? "#004c4c" : "#008080"
  readonly property color face: dark ? "#2b2b2b" : "#c0c0c0"
  readonly property color pressedFace: dark ? "#404040" : "#c0c0c0"
  readonly property color text: dark ? "#d4d4d4" : "#000000"
  readonly property color mutedText: dark ? "#9a9a9a" : "#606060"
  readonly property color field: dark ? "#1f1f1f" : "#ffffff"
  readonly property color fieldText: dark ? "#e0e0e0" : "#000000"
  readonly property color highlight: dark ? "#008080" : "#000080"
  readonly property color highlightText: "#ffffff"
  readonly property color alert: "#ff0000"
  readonly property color edgeLight: dark ? "#666666" : "#ffffff"
  readonly property color edgeMidLight: dark ? "#505050" : "#dfdfdf"
  readonly property color edgeShadow: dark ? "#1a1a1a" : "#808080"
  readonly property color edgeDark: "#000000"

  function refresh(): void {
    dark = modeFile.text().trim() === "dark";
  }

  FileView {
    id: modeFile
    path: Quickshell.env("HOME") + "/.cache/wallust-current-mode"
    watchChanges: true
    printErrors: false
    onLoaded: root.refresh()
    onFileChanged: {
      reload();
      root.refresh();
    }
  }
}
