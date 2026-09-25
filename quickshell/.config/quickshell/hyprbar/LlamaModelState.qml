pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/quickshell/hyprbar/llama-model.sh"
    readonly property bool busy: toggleProcess.running || state === "loading"
    property string state: "off"
    property bool active: false
    property string model: "qwen3.6-35b-a3b"
    property string tooltip: "Local model status unavailable"

    function refresh() {
        if (!statusProcess.running && !toggleProcess.running)
            statusProcess.exec([root.scriptPath, "status"])
    }

    function toggle() {
        if (!toggleProcess.running)
            toggleProcess.exec([root.scriptPath, "toggle"])
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.state = result.state || "off"
            root.active = result.active === true
            root.model = result.model || root.model
            root.tooltip = result.tooltip || "Local model"
        } catch (error) {
            root.state = "unavailable"
            root.active = false
            root.tooltip = "Local model status unavailable"
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
                root.tooltip = "Local model status unavailable"
            }
        }
    }

    Process {
        id: toggleProcess
        onExited: root.refresh()
    }

    Timer {
        interval: root.busy ? 1000 : 3000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
