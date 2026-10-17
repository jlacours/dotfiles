import QtQuick 6.0

// TTS state: a static lips icon (Nerd Font fae-lips, U+E258). Muted when
// idle, accent while speech is generated or played. Click stops the speech.
BarChip {
    id: root

    tooltipText: SpeakState.tooltip
    cursorShape: SpeakState.active ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: SpeakState.stop()

    Text {
        anchors.centerIn: parent
        text: "\ue258"
        color: SpeakState.active ? root.accentColor : root.mutedColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 13
    }
}
