import QtQuick 6.0

// Tailscale status and up/down toggle chip.
Rectangle {
    id: root

    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor
    required property color hoverColor
    required property var panelWindow
    property bool tooltipBelow: false
    property bool onlyWhenActive: false

    visible: !root.onlyWhenActive || TailscaleState.connected
    implicitWidth: 26
    implicitHeight: 24
    radius: 0
    color: tailscaleMouse.containsMouse ? root.hoverColor : "transparent"

    Item {
        anchors.centerIn: parent
        width: 16
        height: 16
        opacity: TailscaleState.busy ? 0.45 : 1.0

        Grid {
            anchors.centerIn: parent
            columns: 3
            rows: 3
            spacing: 1.2

            Repeater {
                model: 9

                delegate: Rectangle {
                    required property int index

                    width: 4.5
                    height: 4.5
                    radius: width / 2
                    color: TailscaleState.connected ? root.accentColor : root.mutedColor
                    opacity: index === 3 || index === 4 || index === 5 || index === 7 ? 1.0 : 0.4
                }
            }
        }
    }

    MouseArea {
        id: tailscaleMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.visible && TailscaleState.available && !TailscaleState.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: TailscaleState.toggle()
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: tailscaleMouse.containsMouse
        labelText: !TailscaleState.available
            ? TailscaleState.tooltip
            : TailscaleState.tooltip + "\nClick to "
                + (TailscaleState.connected ? "disconnect" : "connect")
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
