pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick 6.0

Singleton {
    id: root
    property var apps: ({})
    property bool showWindows: false

    IpcHandler {
        target: "workspaceSegment"
        function toggle(): void { root.showWindows = !root.showWindows }
        function state(): string { return root.showWindows ? "windows" : "overview" }
    }

    // Foot-process probing only matters while windows mode is shown.
    onShowWindowsChanged: if (showWindows) refresh()

    function refresh() {
        if (poll.running || !showWindows)
            return
        const pids = Hyprland.toplevels.values.map(window => String(window.lastIpcObject.pid || 0))
        if (pids.length === 0) {
            apps = ({})
            return
        }
        poll.exec(["python3", Qt.resolvedUrl("window_apps.py").toString().replace(/^file:\/\//, "")].concat(pids))
    }

    Component.onCompleted: refresh()
    Process {
        id: poll
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try { root.apps = JSON.parse(text) }
                catch (error) { root.apps = ({}) }
            }
        }
        onExited: exitCode => { if (exitCode !== 0) root.apps = ({}) }
    }
    Timer {
        interval: 2000
        running: root.showWindows
        repeat: true
        onTriggered: root.refresh()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "movewindow", "movewindowv2"].includes(event.name))
                debounce.restart()
        }
    }
    Timer { id: debounce; interval: 100; onTriggered: root.refresh() }
}
