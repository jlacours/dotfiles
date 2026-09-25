pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/quickshell/hyprbar/llm-corrector.sh"
    readonly property bool busy: toggleProcess.running || state === "starting" || state === "processing"
    property string state: "off"
    property bool active: false
    property bool working: false
    property string tooltip: "Correction status unavailable"

    function refresh() {
        if (!statusProcess.running && !toggleProcess.running)
            statusProcess.exec([root.scriptPath, "status"])
    }

    function toggle() {
        if (!toggleProcess.running && root.state !== "processing")
            toggleProcess.exec([root.scriptPath, "toggle"])
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProcess

        stdout: StdioCollector {
            waitForEnd: true

            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim())
                    root.state = result.state || "off"
                    root.active = result.active === true
                    root.working = result.working === true
                    root.tooltip = result.tooltip || "Correction"
                } catch (error) {
                    root.state = "error"
                    root.active = false
                    root.working = false
                    root.tooltip = "Correction status unavailable"
                }
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.state = "error"
                root.active = false
                root.working = false
                root.tooltip = "Correction status unavailable"
            }
        }
    }

    Process {
        id: toggleProcess
        onExited: root.refresh()
    }

    Timer {
        interval: root.busy ? 400 : 2000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
