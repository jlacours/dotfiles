import QtQuick 6.0

// Local llama.cpp model status, identity tooltip, and safe start/stop toggle.
BarChip {
    id: root

    tooltipText: LlamaModelState.tooltip
    onClicked: LlamaModelState.toggle()

    Text {
        id: icon
        anchors.centerIn: parent
        text: "◈"
        color: LlamaModelState.active || LlamaModelState.state === "loading"
            ? root.accentColor : root.mutedColor
        font.family: "Comic Code"
        font.pixelSize: 13
        opacity: LlamaModelState.busy ? 0.55 : 1.0

        RotationAnimator {
            target: icon
            from: 0
            to: 360
            duration: 1200
            loops: Animation.Infinite
            running: LlamaModelState.state === "loading"
        }
    }
}
