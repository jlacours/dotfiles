pragma Singleton

import Quickshell
import QtQuick 6.0

Singleton {
    id: root

    readonly property bool busy: poller.acting
    property string state: "unavailable"
    property bool active: false
    property bool available: false
    property string tooltip: "Hermes status unavailable"

    function toggle() {
        if (!root.busy && root.available)
            poller.run("toggle")
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.state = result.state || "unavailable"
            root.active = result.active === true
            root.available = result.available === true
            root.tooltip = result.tooltip || "Hermes"
        } catch (error) {
            root.setUnavailable()
        }
    }

    function setUnavailable() {
        root.state = "unavailable"
        root.active = false
        root.available = false
        root.tooltip = "Hermes status unavailable"
    }

    StatusScript {
        id: poller
        script: "hermes.sh"
        interval: root.busy ? 500 : 3000
        onStatusRead: text => root.parseStatus(text)
        onStatusFailed: root.setUnavailable()
    }
}
