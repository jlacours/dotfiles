pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

// Read-only aggregate usage snapshot for the bar. The collector owns provider
// access; this state object only runs the local command and parses its output.
Singleton {
    id: root

    readonly property string command: (Quickshell.env("HOME") || "") + "/.local/bin/ai-usage"
    property string text: "AI —"
    property string tooltip: "AI usage unavailable"
    property string state: "error"
    property string updatedAt: ""
    property bool stale: true
    property var providers: []
    readonly property bool busy: statusProcess.running

    function refresh() {
        if (!statusProcess.running)
            statusProcess.exec([root.command, "--json"])
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            const resultState = result.state === "ok" || result.state === "partial"
                ? result.state : "error"

            root.text = String(result.text || "AI —")
            root.tooltip = String(result.tooltip || "AI usage unavailable")
            root.state = resultState
            root.updatedAt = String(result.updated_at || "")
            root.providers = Array.isArray(result.providers) ? result.providers : []
            root.stale = !root.updatedAt || isStale(root.updatedAt)

            if (root.stale)
                root.tooltip += "\nSnapshot is stale."
        } catch (error) {
            setError("AI usage output is unavailable")
        }
    }

    function isStale(value) {
        const timestamp = Date.parse(value)
        return isNaN(timestamp) || Date.now() - timestamp > 900000
    }

    function setError(message) {
        root.text = "AI —"
        root.tooltip = message
        root.state = "error"
        root.updatedAt = ""
        root.providers = []
        root.stale = true
    }

    function providerFor(providerId) {
        for (let i = 0; i < root.providers.length; i++) {
            if (root.providers[i].id === providerId)
                return root.providers[i]
        }
        return null
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProcess
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseStatus(text)
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.setError("AI usage command failed")
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
