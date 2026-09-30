import QtQuick 6.0

// Tailscale status and up/down toggle chip.
BarChip {
    id: root

    property bool onlyWhenActive: false

    visible: !root.onlyWhenActive || TailscaleState.connected
    tooltipText: !TailscaleState.available
        ? TailscaleState.tooltip
        : TailscaleState.tooltip + "\nClick to "
            + (TailscaleState.connected ? "disconnect" : "connect")
    clickEnabled: root.visible && TailscaleState.available && !TailscaleState.busy
    onClicked: TailscaleState.toggle()

    Item {
        anchors.centerIn: parent
        width: 14
        height: 14
        opacity: TailscaleState.busy ? 0.45 : 1.0

        Grid {
            anchors.centerIn: parent
            columns: 3
            rows: 3
            spacing: 1

            Repeater {
                model: 9

                delegate: Rectangle {
                    required property int index

                    width: 4
                    height: 4
                    radius: width / 2
                    color: TailscaleState.connected ? root.accentColor : root.mutedColor
                    opacity: index === 3 || index === 4 || index === 5 || index === 7 ? 1.0 : 0.4
                }
            }
        }
    }
}
