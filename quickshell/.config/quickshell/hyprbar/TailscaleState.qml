pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/quickshell/hyprbar/tailscale.sh"
    readonly property bool busy: toggleProcess.running
    property bool connected: false
    property bool available: false
    property string icon: "󰖃"
    property string tooltip: "Tailscale status unavailable"

    function refresh() {
        if (!statusProcess.running && !toggleProcess.running)
            statusProcess.exec([root.scriptPath, "status"])
    }

    function toggle() {
        if (root.busy || !root.available)
            return

        toggleProcess.exec([root.scriptPath, "toggle"])
    }

    function parseStatus(text) {
        try {
            const result = JSON.parse(text.trim())
            root.connected = result.class === "tailscale-connected"
            root.available = result.available === true
            root.icon = result.alt || (root.connected ? "󰖂" : "󰖃")
            root.tooltip = result.tooltip || "Tailscale"
        } catch (error) {
            root.connected = false
            root.available = false
            root.icon = "󰖃"
            root.tooltip = "Tailscale status unavailable"
        }
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProcess

        stdout: StdioCollector {
            waitForEnd: true

            onStreamFinished: root.parseStatus(text)
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.connected = false
                root.available = false
                root.tooltip = "Tailscale status unavailable"
            }
        }
    }

    Process {
        id: toggleProcess
        onExited: root.refresh()
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
