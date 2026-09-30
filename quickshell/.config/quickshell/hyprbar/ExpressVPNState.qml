pragma Singleton

import Quickshell
import QtQuick 6.0

Singleton {
    id: root

    readonly property bool active: connectionState === "Connected"
    readonly property bool busy: poller.acting
        || connectionState === "Connecting"
        || connectionState === "Reconnecting"
        || connectionState === "DisconnectingToReconnect"
        || connectionState === "Disconnecting"
    property string connectionState: "Disconnected"

    function toggle() {
        if (!root.busy)
            poller.run(root.active ? "disconnect" : "connect")
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.connectionState = result.state || "Disconnected"
        } catch (error) {
            root.connectionState = "Disconnected"
        }
    }

    StatusScript {
        id: poller
        script: "expressvpn.sh"
        onStatusRead: text => root.parseStatus(text)
        onStatusFailed: root.connectionState = "Disconnected"
    }
}
