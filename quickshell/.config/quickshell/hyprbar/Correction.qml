import QtQuick 6.0

// Dedicated local grammar-correction model status and toggle chip.
BarChip {
    id: root

    tooltipText: CorrectionState.tooltip
    clickEnabled: !CorrectionState.working
    onClicked: CorrectionState.toggle()

    Text {
        id: correctionIcon
        anchors.centerIn: parent
        text: CorrectionState.working ? "✦" : "󰏫"
        color: CorrectionState.active ? root.accentColor : root.mutedColor
        font.family: CorrectionState.working ? "monospace" : "Symbols Nerd Font Mono"
        font.pixelSize: CorrectionState.working ? 14 : 13
        opacity: CorrectionState.state === "starting" ? 0.5 : 1.0

        RotationAnimator {
            target: correctionIcon
            from: 0
            to: 360
            duration: 800
            loops: Animation.Infinite
            running: CorrectionState.working
        }

        SequentialAnimation on scale {
            loops: Animation.Infinite
            running: CorrectionState.working
            NumberAnimation { to: 1.22; duration: 240; easing.type: Easing.OutQuad }
            NumberAnimation { to: 0.88; duration: 240; easing.type: Easing.InOutQuad }
            NumberAnimation { to: 1.0; duration: 240; easing.type: Easing.OutQuad }
        }
    }
}
