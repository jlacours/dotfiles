pragma Singleton

import Quickshell
import QtQuick 6.0

Singleton {
    id: root

    readonly property bool busy: poller.acting || state === "loading"
    property string state: "off"
    property bool active: false
    property string tooltip: "Local model status unavailable"

    function toggle() {
        if (!poller.acting)
            poller.run("toggle")
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.state = result.state || "off"
            root.active = result.active === true
            root.tooltip = result.tooltip || "Local model"
        } catch (error) {
            root.setUnavailable()
        }
    }

    function setUnavailable() {
        root.state = "unavailable"
        root.active = false
        root.tooltip = "Local model status unavailable"
    }

    StatusScript {
        id: poller
        script: "llama-model.sh"
        interval: root.busy ? 1000 : 3000
        onStatusRead: text => root.parseStatus(text)
        onStatusFailed: root.setUnavailable()
    }
}
