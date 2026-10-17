import QtQuick 6.0

// TTS state: a simple, static mouth. Muted when idle, accent while speech is
// generated or played. Click stops the current speech.
BarChip {
    id: root

    tooltipText: SpeakState.tooltip
    cursorShape: SpeakState.active ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: SpeakState.stop()

    Text {
        anchors.centerIn: parent
        text: "◡"
        color: SpeakState.active ? root.accentColor : root.mutedColor
        font.family: "Comic Code"
        font.pixelSize: 13
    }
}
