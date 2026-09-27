import QtQuick 6.0

// ExpressVPN status and toggle chip.
Rectangle {
    id: root

    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor
    required property color hoverColor
    required property var panelWindow
    property bool tooltipBelow: false

    implicitWidth: 23
    implicitHeight: 22
    radius: 0
    color: vpnMouse.containsMouse ? root.hoverColor : "transparent"

    Text {
        anchors.centerIn: parent
        text: ExpressVPNState.active ? "󰒘" : "󰒙"
        color: ExpressVPNState.active ? root.accentColor : root.mutedColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 13
        opacity: ExpressVPNState.busy ? 0.45 : 1.0
    }

    MouseArea {
        id: vpnMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: !ExpressVPNState.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: ExpressVPNState.toggle()
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: vpnMouse.containsMouse
        labelText: ExpressVPNState.active
            ? "VPN connected — click to disconnect"
            : ExpressVPNState.busy
                ? "VPN " + ExpressVPNState.connectionState.toLowerCase()
                : "VPN disconnected — click to connect"
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
