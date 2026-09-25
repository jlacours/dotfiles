pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/quickshell/hyprbar/hypridle.sh"
    readonly property bool busy: toggleProcess.running
    property string state: "hypridle-off"
    property bool active: false
    property bool partial: false
    property bool inhibiting: false
    property bool available: true
    property string icon: "󰈉"
    property string tooltip: "Idle timeout status unavailable"

    function refresh() {
        if (!statusProcess.running && !toggleProcess.running)
            statusProcess.exec([root.scriptPath, "status"])
    }

    function toggle() {
        if (!root.busy && root.available)
            toggleProcess.exec([root.scriptPath, "toggle"])
    }

    function parseStatus(text) {
        try {
            const result = JSON.parse(text.trim())
            root.state = result.class || "hypridle-off"
            root.active = result.active === true
            root.partial = result.partial === true
            root.inhibiting = result.inhibiting === true
            root.available = result.available !== false
            root.icon = result.alt || "󰈉"
            root.tooltip = result.tooltip || "Idle timeout"
        } catch (error) {
            root.state = "hypridle-unavailable"
            root.active = false
            root.partial = false
            root.inhibiting = false
            root.available = false
            root.tooltip = "Idle timeout status unavailable"
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
                root.state = "hypridle-unavailable"
                root.active = false
                root.partial = false
                root.inhibiting = false
                root.available = false
                root.tooltip = "Idle timeout status unavailable"
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
