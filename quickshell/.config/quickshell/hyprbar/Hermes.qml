import QtQuick 6.0

// Hermes gateway plus Signal transport status and toggle.
BarChip {
    id: root

    tooltipText: HermesState.tooltip
    clickEnabled: HermesState.available && !HermesState.busy
    onClicked: HermesState.toggle()

    Text {
        anchors.centerIn: parent
        text: "☤"
        color: HermesState.active || HermesState.state === "partial"
            ? root.accentColor : root.mutedColor
        font.family: "Comic Code"
        font.pixelSize: 14
        opacity: HermesState.busy ? 0.5 : 1.0

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: HermesState.busy
            NumberAnimation { to: 0.35; duration: 450 }
            NumberAnimation { to: 1.0; duration: 450 }
        }
    }
}
