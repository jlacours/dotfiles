import QtQuick 6.0

// ExpressVPN status and toggle chip.
BarChip {
    id: root

    tooltipText: ExpressVPNState.active
        ? "VPN connected — click to disconnect"
        : ExpressVPNState.busy
            ? "VPN " + ExpressVPNState.connectionState.toLowerCase()
            : "VPN disconnected — click to connect"
    clickEnabled: !ExpressVPNState.busy
    onClicked: ExpressVPNState.toggle()

    Text {
        anchors.centerIn: parent
        text: ExpressVPNState.active ? "󰒘" : "󰒙"
        color: ExpressVPNState.active ? root.accentColor : root.mutedColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 13
        opacity: ExpressVPNState.busy ? 0.45 : 1.0
    }
}
