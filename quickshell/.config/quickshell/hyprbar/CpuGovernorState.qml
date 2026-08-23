pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/hypr/scripts/cpu-governor.sh"
    readonly property bool performance: governor === "performance"
    readonly property bool busy: toggleProcess.running
    property string governor: "unknown"
    property bool available: false

    function refresh() {
        if (!statusProcess.running && !toggleProcess.running)
            statusProcess.exec(["/usr/bin/bash", root.scriptPath, "status"])
    }

    function toggle() {
        if (root.busy || !root.available)
            return

        toggleProcess.exec(["/usr/bin/bash", root.scriptPath, "toggle"])
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProcess

        stdout: StdioCollector {
            waitForEnd: true

            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim())
                    root.governor = result.governor || "unknown"
                    root.available = result.available === true
                } catch (error) {
                    root.governor = "unknown"
                    root.available = false
                }
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.governor = "unknown"
                root.available = false
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
