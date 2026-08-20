import QtQuick 6.0
import QtQuick.Controls 6.0

Rectangle {
    id: root

    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor
    required property color hoverColor

    implicitWidth: 26
    implicitHeight: 24
    radius: 0
    color: gameModeMouse.containsMouse ? root.hoverColor : "transparent"

    Text {
        anchors.centerIn: parent
        text: "󰊴"
        color: GameModeState.active ? root.accentColor : root.mutedColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 15
        opacity: GameModeState.busy ? 0.45 : 1.0
    }

    MouseArea {
        id: gameModeMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: !GameModeState.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: GameModeState.toggle()
    }

    ToolTip {
        visible: gameModeMouse.containsMouse
        text: GameModeState.active
            ? "Game mode on — click to restore services"
            : "Game mode off — click to pause background services"
    }
}
