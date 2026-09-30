pragma Singleton

import Quickshell
import QtQuick 6.0

Singleton {
    id: root

    readonly property bool busy: poller.acting
    property bool active: false
    property bool partial: false
    property bool inhibiting: false
    property bool available: true
    property string icon: "󰈉"
    property string tooltip: "Idle timeout status unavailable"

    function toggle() {
        if (!root.busy && root.available)
            poller.run("toggle")
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.active = result.active === true
            root.partial = result.partial === true
            root.inhibiting = result.inhibiting === true
            root.available = result.available !== false
            root.icon = result.alt || "󰈉"
            root.tooltip = result.tooltip || "Idle timeout"
        } catch (error) {
            root.setUnavailable()
        }
    }

    function setUnavailable() {
        root.active = false
        root.partial = false
        root.inhibiting = false
        root.available = false
        root.tooltip = "Idle timeout status unavailable"
    }

    StatusScript {
        id: poller
        script: "hypridle.sh"
        onStatusRead: text => root.parseStatus(text)
        onStatusFailed: root.setUnavailable()
    }
}
