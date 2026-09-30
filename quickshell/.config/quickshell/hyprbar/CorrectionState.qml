pragma Singleton

import Quickshell
import QtQuick 6.0

Singleton {
    id: root

    readonly property bool busy: poller.acting || state === "starting" || state === "processing"
    property string state: "off"
    property bool active: false
    property bool working: false
    property string tooltip: "Correction status unavailable"

    function toggle() {
        if (!poller.acting && root.state !== "processing")
            poller.run("toggle")
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.state = result.state || "off"
            root.active = result.active === true
            root.working = result.working === true
            root.tooltip = result.tooltip || "Correction"
        } catch (error) {
            root.setUnavailable()
        }
    }

    function setUnavailable() {
        root.state = "error"
        root.active = false
        root.working = false
        root.tooltip = "Correction status unavailable"
    }

    StatusScript {
        id: poller
        script: "llm-corrector.sh"
        interval: root.busy ? 400 : 2000
        onStatusRead: text => root.parseStatus(text)
        onStatusFailed: root.setUnavailable()
    }
}
