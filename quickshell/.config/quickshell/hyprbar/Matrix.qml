import QtQuick 6.0
import QtQuick.Effects
import Quickshell.Widgets

// Local Matrix homeserver and its Hermes gateway.
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
    color: matrixMouse.containsMouse ? root.hoverColor : "transparent"

    IconImage {
        id: matrixLogo
        anchors.centerIn: parent
        implicitSize: 20
        source: Qt.resolvedUrl("matrix-mask.svg")
        asynchronous: true
        opacity: MatrixState.busy ? 0.55
            : MatrixState.active ? 1.0
            : MatrixState.partial ? 0.8 : 0.55

        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: root.accentColor
        }

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: MatrixState.busy
            NumberAnimation { to: 0.35; duration: 450 }
            NumberAnimation { to: 1.0; duration: 450 }
        }
    }

    MouseArea {
        id: matrixMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: MatrixState.available && !MatrixState.busy
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: MatrixState.toggle()
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: matrixMouse.containsMouse
        labelText: MatrixState.tooltip
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
