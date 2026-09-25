pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string statePath: "/tmp/quickshell-layout.state"
    property string layout: ""
    property string direction: "up"
    property real expires: 0
    property int revision: 0
    property int tick: 0
    readonly property bool visible: root.layout !== "" && root.tick >= 0 && Date.now() < root.expires

    function scheduleExpiry() {
        const remaining = root.expires - Date.now()

        if (remaining > 0) {
            expiryTimer.interval = Math.max(1, remaining)
            expiryTimer.restart()
        } else {
            root.tick += 1
        }
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            const nextLayout = result.layout || ""
            const nextDirection = result.direction === "down" ? "down" : "up"
            const nextExpires = Number(result.expires) || 0

            if (root.layout !== nextLayout || root.direction !== nextDirection || root.expires !== nextExpires) {
                root.layout = nextLayout
                root.direction = nextDirection
                root.expires = nextExpires
                root.revision += 1
                root.tick += 1
                root.scheduleExpiry()
            }
        } catch (error) {
            root.layout = ""
            root.expires = 0
            root.tick += 1
        }
    }

    FileView {
        id: stateFile

        path: root.statePath
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: root.parseStatus(text())
        onFileChanged: reload()
    }

    Timer {
        id: expiryTimer

        repeat: false
        onTriggered: root.scheduleExpiry()
    }
}
