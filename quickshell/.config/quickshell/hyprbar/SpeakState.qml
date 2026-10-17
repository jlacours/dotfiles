pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

// TTS speak status from speak-status.sh. Polls faster while speech is active.
Singleton {
    id: root

    readonly property bool busy: poller.acting
    property string state: "idle"
    property bool active: false
    property string tooltip: "Speech idle"
    // speak pushes its state over IPC; polling only covers missed pushes (e.g. a killed speak).
    property real pushedAt: 0

    function applyState(state) {
        root.state = state
        root.active = state === "generating" || state === "talking"
        root.tooltip = state === "talking" ? "Speaking\nClick to stop"
            : state === "generating" ? "Preparing speech\nClick to stop" : "Speech idle"
    }

    function stop() {
        if (!root.busy && root.active)
            poller.run("stop")
    }

    function parseStatus(value) {
        if (Date.now() - root.pushedAt < 1500)
            return
        try {
            const result = JSON.parse(value.trim())
            root.state = result.state || "idle"
            root.active = result.active === true
            root.tooltip = result.tooltip || "Speech"
        } catch (error) {
            root.setUnavailable()
        }
    }

    function setUnavailable() {
        root.state = "unavailable"
        root.active = false
        root.tooltip = "Speech status unavailable"
    }

    IpcHandler {
        target: "speak"

        function state(state: string): void {
            root.pushedAt = Date.now()
            root.applyState(state)
        }
    }

    StatusScript {
        id: poller
        script: "speak-status.sh"
        interval: root.active ? 500 : 1000
        onStatusRead: text => root.parseStatus(text)
        onStatusFailed: root.setUnavailable()
    }
}
