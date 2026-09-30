pragma Singleton

import Quickshell
import QtQuick 6.0

Singleton {
    id: root

    readonly property bool busy: poller.acting
    property bool connected: false
    property bool available: false
    property string tooltip: "Tailscale status unavailable"

    function toggle() {
        if (!root.busy && root.available)
            poller.run("toggle")
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.connected = result.class === "tailscale-connected"
            root.available = result.available === true
            root.tooltip = result.tooltip || "Tailscale"
        } catch (error) {
            root.setUnavailable()
        }
    }

    function setUnavailable() {
        root.connected = false
        root.available = false
        root.tooltip = "Tailscale status unavailable"
    }

    StatusScript {
        id: poller
        script: "tailscale.sh"
        onStatusRead: text => root.parseStatus(text)
        onStatusFailed: root.setUnavailable()
    }
}
