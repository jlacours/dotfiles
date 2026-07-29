import QtQuick
import Quickshell

// Canonical Win95 close control for QML-owned chrome. The image is the exact
// Labwc 18x16 crispEdges asset, resolved through the selected runtime variant.
Item {
  id: root

  signal clicked()

  implicitWidth: 18
  implicitHeight: 16

  Image {
    anchors.fill: parent
    source: "file://" + Quickshell.env("HOME")
      + "/.local/share/themes/win95-current/openbox-3/close-active.svg"
    sourceSize: Qt.size(18, 16)
    fillMode: Image.PreserveAspectFit
    smooth: false
    cache: false
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.clicked()
  }
}
