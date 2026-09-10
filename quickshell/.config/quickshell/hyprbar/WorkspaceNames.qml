import Quickshell.Hyprland
import QtQuick 6.0

Item {
    id: root

    visible: false

    // Bumps after an IPC refresh so nameFor() bindings re-evaluate even when
    // Hyprland updates an existing workspace object in place.
    property int revision: 0

    function nameFor(workspaceId) {
        const workspaces = revision >= 0 ? Hyprland.workspaces.values : []
        let title = workspaceId.toString()

        for (let index = 0; index < workspaces.length; index++) {
            const workspace = workspaces[index]

            if (workspace.id === workspaceId) {
                title = workspace.name || title
                break
            }
        }

        return title === workspaceId.toString()
            ? title
            : workspaceId.toString() + ": " + title
    }

    function refreshAfterRename() {
        Hyprland.refreshWorkspaces()
        refreshTimer.restart()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "renameworkspace")
                root.refreshAfterRename()
        }
    }

    Timer {
        id: refreshTimer

        interval: 50
        onTriggered: root.revision += 1
    }
}
