import Quickshell
import Quickshell.Io
import QtQuick 6.0

// Polls "<script> status" from this directory and runs its actions. Polling
// pauses while an action runs and resumes with an immediate refresh after it.
Scope {
    id: root

    required property string script
    property int interval: 3000
    readonly property string path: (Quickshell.env("HOME") || "") + "/.config/quickshell/hyprbar/" + root.script
    readonly property bool acting: actionProcess.running

    signal statusRead(string text)
    signal statusFailed()

    function refresh() {
        if (!statusProcess.running && !actionProcess.running)
            statusProcess.exec([root.path, "status"])
    }

    function run(action) {
        actionProcess.exec([root.path, action])
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProcess
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.statusRead(text)
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.statusFailed()
        }
    }

    Process {
        id: actionProcess
        onExited: root.refresh()
    }

    Timer {
        interval: root.interval
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
