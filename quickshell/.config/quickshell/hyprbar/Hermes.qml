import QtQuick 6.0

// Hermes gateway plus Signal transport status and toggle.
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
    color: hermesMouse.containsMouse ? root.hoverColor : "transparent"

    Text {
        id: icon
        anchors.centerIn: parent
        text: "☤"
        color: HermesState.active || HermesState.state === "partial"
            ? root.accentColor : root.mutedColor
        font.family: "Comic Code"
        font.pixelSize: 18
        opacity: HermesState.busy ? 0.5 : 1.0

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: HermesState.busy
            NumberAnimation { to: 0.35; duration: 450 }
            NumberAnimation { to: 1.0; duration: 450 }
        }
    }

    MouseArea {
        id: hermesMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: HermesState.available && !HermesState.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: HermesState.toggle()
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: hermesMouse.containsMouse
        labelText: HermesState.tooltip
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
