pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/quickshell/hyprbar/hermes.sh"
    readonly property bool busy: toggleProcess.running
    property string state: "unavailable"
    property bool active: false
    property bool available: false
    property string tooltip: "Hermes status unavailable"

    function refresh() {
        if (!statusProcess.running && !toggleProcess.running)
            statusProcess.exec([root.scriptPath, "status"])
    }

    function toggle() {
        if (!root.busy && root.available)
            toggleProcess.exec([root.scriptPath, "toggle"])
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.state = result.state || "unavailable"
            root.active = result.active === true
            root.available = result.available === true
            root.tooltip = result.tooltip || "Hermes"
        } catch (error) {
            root.state = "unavailable"
            root.active = false
            root.available = false
            root.tooltip = "Hermes status unavailable"
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
                root.state = "unavailable"
                root.active = false
                root.available = false
                root.tooltip = "Hermes status unavailable"
            }
        }
    }

    Process {
        id: toggleProcess
        onExited: root.refresh()
    }

    Timer {
        interval: root.busy ? 500 : 3000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
