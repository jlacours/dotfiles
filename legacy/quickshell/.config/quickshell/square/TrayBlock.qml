import QtQuick
import Quickshell.Services.SystemTray
import "." as Square

// System tray icons, shown in a row. Game mode toggle sits first.
Row {
  id: root

  spacing: Theme.padSm
  height: Theme.barHeight

  Square.GameModeBlock {
    anchors.verticalCenter: parent.verticalCenter
  }

  Repeater {
    model: SystemTray.items

    TrayItem {
      required property var modelData
      anchors.verticalCenter: parent.verticalCenter
      item: modelData
      iconSize: 16
    }
  }
}
