import QtQuick
import "." as Square

// ExpressVPN indicator: "EVPN" tag + location/OFF state. Always visible so a
// dropped VPN is never silently invisible. Left-click toggles connect/disconnect.
// Degrades to a dim "OFF" when the daemon/CLI is unavailable, and a critical
// "OFF" when installed but disconnected. See ExpressVpnState.qml.
Item {
  id: root

  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  // Fixed-width floor so the OFF state never nudges its neighbours; the
  // connected location abbreviation (up to ~4 chars, see expressvpn.sh's
  // abbreviate_location) may still grow past this floor.
  TextMetrics {
    id: valueMetrics
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontMd
    font.bold: true
    text: "OFF"
  }

  function valueText() {
    const s = Square.ExpressVpnState
    return s.connected ? s.shortLocation : "OFF"
  }

  function stateColor() {
    const s = Square.ExpressVpnState
    if (s.state === "Unavailable") return Theme.textDim
    if (s.connected) return Theme.success
    return Theme.critical
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.padSm

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "EVPN"
      color: Theme.textMuted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSm
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(valueMetrics.width, implicitWidth)
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
    onClicked: Square.ExpressVpnState.toggle()
  }
}
