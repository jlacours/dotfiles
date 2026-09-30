import QtQuick 6.0

// Hypridle timeout and fullscreen-inhibitor status chip.
BarChip {
    id: root

    tooltipText: HypridleState.tooltip
    clickEnabled: HypridleState.available && !HypridleState.busy
    onClicked: HypridleState.toggle()

    Text {
        anchors.centerIn: parent
        text: HypridleState.icon
        color: HypridleState.inhibiting
            ? "#e5a84b"
            : HypridleState.active ? root.accentColor : root.mutedColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 13
        opacity: HypridleState.busy || (HypridleState.partial && !HypridleState.inhibiting) ? 0.55 : 1.0
    }
}
