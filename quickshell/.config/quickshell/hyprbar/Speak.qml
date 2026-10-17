import QtQuick 6.0

// TTS mouth: closed line when idle, dashed line while speech is generated,
// opening and closing while it plays. Click stops the current speech.
BarChip {
    id: root

    readonly property var talkFrames: ["─", "◡", "○", "●", "○", "◡"]
    readonly property bool talking: SpeakState.state === "talking"
    readonly property bool generating: SpeakState.state === "generating"

    tooltipText: SpeakState.tooltip
    cursorShape: SpeakState.active ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: SpeakState.stop()

    Text {
        id: mouth
        anchors.centerIn: parent
        property int frameIndex: 0
        text: root.talking ? root.talkFrames[frameIndex]
            : root.generating ? "┄"
            : "─"
        color: SpeakState.active ? root.accentColor : root.mutedColor
        font.family: "Comic Code"
        font.pixelSize: 13

        Timer {
            interval: 140
            running: root.talking
            repeat: true
            onTriggered: mouth.frameIndex = (mouth.frameIndex + 1) % root.talkFrames.length
        }

        SequentialAnimation {
            id: pulse
            loops: Animation.Infinite
            running: root.generating
            onRunningChanged: if (!running) mouth.opacity = 1.0
            NumberAnimation { target: mouth; property: "opacity"; to: 0.35; duration: 700 }
            NumberAnimation { target: mouth; property: "opacity"; to: 1.0; duration: 700 }
        }
    }
}
