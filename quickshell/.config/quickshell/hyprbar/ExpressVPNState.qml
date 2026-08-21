pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/quickshell/hyprbar/expressvpn.sh"
    readonly property bool active: connectionState === "Connected"
    readonly property bool busy: toggleProcess.running
        || connectionState === "Connecting"
        || connectionState === "Reconnecting"
        || connectionState === "DisconnectingToReconnect"
        || connectionState === "Disconnecting"
    property string connectionState: "Disconnected"

    function refresh() {
        if (!statusProcess.running && !toggleProcess.running)
            statusProcess.exec([root.scriptPath, "status"])
    }

    function toggle() {
        if (root.busy)
            return

        toggleProcess.exec([root.scriptPath, root.active ? "disconnect" : "connect"])
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProcess

        stdout: StdioCollector {
            waitForEnd: true

            onStreamFinished: {
                try {
                    const result = JSON.parse(text.trim())
                    root.connectionState = result.state || "Disconnected"
                } catch (error) {
                    root.connectionState = "Disconnected"
                }
            }
        }

        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.connectionState = "Disconnected"
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
