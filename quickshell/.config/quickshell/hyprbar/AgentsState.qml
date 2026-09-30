pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root
    property string state: "unknown"
    property string text: "?"
    property string tooltip: "Workflow status unavailable"
    function refresh() {
        if (!poll.running)
            poll.exec([(Quickshell.env("HOME") || "") + "/.local/bin/agent-board", "--bar"])
    }
    Component.onCompleted: refresh()
    Process {
        id: poll
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const value = JSON.parse(text.trim())
                    root.state = value.state || "unknown"
                    root.text = value.text || "?"
                    root.tooltip = value.tooltip || "Workflow status unavailable"
                } catch (error) {
                    root.state = "unknown"
                    root.text = "?"
                    root.tooltip = "Workflow status unavailable"
                }
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                root.state = "unknown"
                root.text = "?"
                root.tooltip = "Workflow status unavailable"
            }
        }
    }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: root.refresh() }
}
