import QtQuick
import "." as Square

// SearXNG + VPN sidecar indicator: "XNG" tag + ON/OFF state. Left-click toggles the stack
// (start/stop the two user units); right-click opens the combined service
// log. Degrades to a dim "OFF" when the stack is not installed.
// See SearxngVpnState.qml.
Item {
  id: root

  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  // Fixed-width slot so toggling ON/OFF never nudges its neighbours.
  TextMetrics {
    id: valueMetrics
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontMd
    font.bold: true
    text: "OFF"
  }

  function valueText() {
    const s = Square.SearxngVpnState
    return s.ok ? "ON" : "OFF"
  }

  function stateColor() {
    const s = Square.SearxngVpnState
    if (!s.installed) return Theme.textDim
    if (s.ok) return Theme.success
    return Theme.critical
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.padSm

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "XNG"
      color: Theme.textMuted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSm
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: valueMetrics.width
      horizontalAlignment: Text.AlignLeft
      text: root.valueText()
      color: root.stateColor()
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontMd
      font.bold: true
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) {
        Square.SearxngVpnState.openLogs()
      } else {
        Square.SearxngVpnState.toggle()
      }
    }
  }
}
