pragma Singleton

import QtQuick 6.0
import Quickshell
import Quickshell.Io

// Shared toggle state keeps both monitor bars on the same AI-slot view:
// the compact rotating badge, or every provider side by side.
// Also scriptable: `qs ipc -c hyprbar call aiSlot toggle`.
Singleton {
    id: root

    property bool expanded: false

    function toggle() {
        root.expanded = !root.expanded
    }

    IpcHandler {
        target: "aiSlot"

        function toggle(): void {
            root.toggle()
        }
    }
}
