import QtQuick 6.0

// Game mode status and toggle chip.
BarChip {
    id: root

    tooltipText: GameModeState.active
        ? "Game mode on — click to restore services"
        : "Game mode off — click to pause background services"
    clickEnabled: !GameModeState.busy
    onClicked: GameModeState.toggle()

    Text {
        anchors.centerIn: parent
        text: "󰊴"
        color: GameModeState.active ? root.accentColor : root.mutedColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 13
        opacity: GameModeState.busy ? 0.45 : 1.0
    }
}
