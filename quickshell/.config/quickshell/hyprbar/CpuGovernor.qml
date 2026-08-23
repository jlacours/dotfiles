import QtQuick 6.0

// CPU governor status and performance/powersave toggle chip.
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
    color: governorMouse.containsMouse ? root.hoverColor : "transparent"

    Text {
        anchors.centerIn: parent
        text: CpuGovernorState.performance ? "󰓅" : "󰾆"
        color: CpuGovernorState.performance ? root.accentColor : root.mutedColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 15
        opacity: CpuGovernorState.busy ? 0.45 : 1.0
    }

    MouseArea {
        id: governorMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: CpuGovernorState.available && !CpuGovernorState.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: CpuGovernorState.toggle()
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: governorMouse.containsMouse
        labelText: !CpuGovernorState.available
            ? "CPU governor unavailable"
            : CpuGovernorState.performance
                ? "CPU: performance — click for powersave"
                : "CPU: " + CpuGovernorState.governor + " — click for performance"
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
