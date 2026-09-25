pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/quickshell/hyprbar/matrix.sh"
    readonly property bool busy: toggleProcess.running
    property string state: "matrix-off"
    property bool active: false
    property bool partial: false
    property bool available: true
    property string tooltip: "Matrix status unavailable"

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
            root.state = result.class || "matrix-off"
            root.active = result.active === true
            root.partial = result.partial === true
            root.available = result.available !== false
            root.tooltip = result.tooltip || "Matrix homeserver"
        } catch (error) {
            root.state = "matrix-unavailable"
            root.active = false
            root.partial = false
            root.available = false
            root.tooltip = "Matrix status unavailable"
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
                root.state = "matrix-unavailable"
                root.active = false
                root.partial = false
                root.available = false
                root.tooltip = "Matrix status unavailable"
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
