pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    property bool available: false
    property var groups: []
    property int count: 0
    property bool attention: false
    property date now: new Date()
    readonly property string tooltip: available
        ? (count === 0 ? "No open todos" : groups.map(group => group.name + ": " + group.items.length).join("\n"))
        : "Todos unavailable"

    function overdue(todo) {
        return todo.due !== null && todo.due * 1000 < root.now.getTime()
    }

    function setUnavailable() {
        available = false
        groups = []
        count = 0
        attention = false
    }

    function parseStatus(text) {
        try {
            const data = JSON.parse(text)
            if (!Array.isArray(data))
                throw new Error("Expected todo array")
            const open = data.filter(todo => !todo.completed).map(todo => ({
                id: todo.id,
                list: String(todo.list || "personal"),
                summary: String(todo.summary || "Untitled todo"),
                due: todo.due !== null && todo.due !== undefined && isFinite(Number(todo.due))
                    ? Number(todo.due) : null,
                priority: Number(todo.priority) || 0
            }))
            // iCalendar priority: 1 is highest, 9 lowest, 0 unspecified.
            open.sort((a, b) => (a.due ?? Infinity) - (b.due ?? Infinity)
                || (a.priority || 10) - (b.priority || 10)
                || a.summary.localeCompare(b.summary))
            const names = Array.from(new Set(open.map(todo => todo.list))).sort()
            root.groups = names.map(name => ({ name: name, items: open.filter(todo => todo.list === name) }))
            root.count = open.length
            const tomorrow = new Date(root.now)
            tomorrow.setHours(24, 0, 0, 0)
            root.attention = open.some(todo => todo.due !== null && todo.due * 1000 < tomorrow.getTime())
            root.available = true
        } catch (error) {
            root.setUnavailable()
        }
    }

    function refresh() {
        root.now = new Date()
        if (!poll.running)
            poll.exec(["/bin/sh", "-c", 'exec "$HOME/.local/bin/todo" --porcelain list 2>/dev/null'])
    }

    Component.onCompleted: refresh()

    Process {
        id: poll
        // Parse when stdout is complete: `exited` can fire before the collector
        // finishes. A failed run prints no JSON, which parseStatus rejects.
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseStatus(text)
        }
        onExited: function(exitCode) {
            if (exitCode !== 0)
                root.setUnavailable()
        }
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
