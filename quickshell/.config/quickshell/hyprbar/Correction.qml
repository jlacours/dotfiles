import QtQuick 6.0

// Dedicated local grammar-correction model status and toggle chip.
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
    color: correctionMouse.containsMouse ? root.hoverColor : "transparent"

    Text {
        id: correctionIcon
        anchors.centerIn: parent
        text: CorrectionState.working ? "✦" : "󰏫"
        color: CorrectionState.active ? root.accentColor : root.mutedColor
        font.family: CorrectionState.working ? "monospace" : "Symbols Nerd Font Mono"
        font.pixelSize: CorrectionState.working ? 17 : 15
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

    MouseArea {
        id: correctionMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: !CorrectionState.working
        cursorShape: Qt.PointingHandCursor
        onClicked: CorrectionState.toggle()
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: correctionMouse.containsMouse
        labelText: CorrectionState.tooltip
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
