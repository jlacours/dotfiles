import QtQuick
import "." as Square

// Game mode tray indicator. Controller glyph: grey (textDim) when off,
// accent colour when on. Left-click toggles game mode via GameModeState.
Item {
  id: root

  implicitHeight: Theme.barHeight
  implicitWidth: label.implicitWidth

  Text {
    id: label
    anchors.centerIn: parent
    text: "󰊴"
    color: Square.GameModeState.active ? Theme.accent : Theme.textDim
    font.family: Theme.iconFamily
    font.pixelSize: 16
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: Square.GameModeState.toggle()
  }
}
