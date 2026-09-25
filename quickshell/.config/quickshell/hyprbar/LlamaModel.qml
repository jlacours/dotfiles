import QtQuick 6.0

// Local llama.cpp model status, identity tooltip, and safe start/stop toggle.
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
    color: modelMouse.containsMouse ? root.hoverColor : "transparent"

    Text {
        id: icon
        anchors.centerIn: parent
        text: "◈"
        color: LlamaModelState.active || LlamaModelState.state === "loading"
            ? root.accentColor : root.mutedColor
        font.family: "Comic Code"
        font.pixelSize: 16
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

    MouseArea {
        id: modelMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: LlamaModelState.toggle()
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: modelMouse.containsMouse
        labelText: LlamaModelState.tooltip
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
