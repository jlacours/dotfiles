pragma Singleton

import Quickshell
import QtQuick 6.0

Singleton {
    id: root

    readonly property bool busy: poller.acting
    property bool active: false
    property bool partial: false
    property bool available: true
    property string tooltip: "Matrix status unavailable"

    function toggle() {
        if (!root.busy && root.available)
            poller.run("toggle")
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.active = result.active === true
            root.partial = result.partial === true
            root.available = result.available !== false
            root.tooltip = result.tooltip || "Matrix homeserver"
        } catch (error) {
            root.setUnavailable()
        }
    }

    function setUnavailable() {
        root.active = false
        root.partial = false
        root.available = false
        root.tooltip = "Matrix status unavailable"
    }

    StatusScript {
        id: poller
        script: "matrix.sh"
        interval: root.busy ? 500 : 3000
        onStatusRead: text => root.parseStatus(text)
        onStatusFailed: root.setUnavailable()
    }
}
