pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/hypr/scripts/game-mode.sh"
    readonly property bool busy: toggleProcess.running
    property bool active: false

    function refresh() {
        if (!statusProcess.running)
            statusProcess.exec([root.scriptPath, "status"])
    }

    function toggle() {
        if (toggleProcess.running)
            return

        toggleProcess.exec([root.scriptPath, "toggle"])
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProcess
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.active = text.trim() === "on"
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
