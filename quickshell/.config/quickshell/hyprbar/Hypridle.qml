import QtQuick 6.0

// Hypridle timeout and fullscreen-inhibitor status chip.
Rectangle {
    id: root

    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor
    required property color hoverColor
    required property var panelWindow
    property bool tooltipBelow: false

    implicitWidth: 26
    implicitHeight: 24
    radius: 0
    color: hypridleMouse.containsMouse ? root.hoverColor : "transparent"

    Text {
        anchors.centerIn: parent
        text: HypridleState.icon
        color: HypridleState.inhibiting
            ? "#e5a84b"
            : HypridleState.active ? root.accentColor : root.mutedColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 15
        opacity: HypridleState.busy || (HypridleState.partial && !HypridleState.inhibiting) ? 0.55 : 1.0
    }

    MouseArea {
        id: hypridleMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: HypridleState.available && !HypridleState.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: HypridleState.toggle()
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: hypridleMouse.containsMouse
        labelText: HypridleState.tooltip
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
