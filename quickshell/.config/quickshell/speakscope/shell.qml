import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick 6.4

// Mirrored speech oscilloscopes around a spinning tesseract at the bottom of
// the focused screen while `speak` talks. A separate quickshell config on
// purpose: animating inside the hyprbar process re-renders its windows every
// frame and pegs a CPU core.
// speak pushes its state over IPC (`qs -c speakscope ipc call speak state X`).
ShellRoot {
    id: root

    property string state: "idle"
    readonly property bool active: state === "generating" || state === "talking"

    IpcHandler {
        target: "speak"

        function state(state: string): void {
            root.state = state
        }
    }

    // Watchdog: a killed speak never pushes "idle", so check while active.
    Timer {
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: if (!watchdog.running) watchdog.running = true
    }

    Process {
        id: watchdog
        command: [(Quickshell.env("HOME") || "") + "/.config/quickshell/hyprbar/speak-status.sh", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    if (JSON.parse(text).state === "idle")
                        root.state = "idle"
                } catch (error) {}
            }
        }
    }

    PanelWindow {
        id: window

        // Follow the focused monitor; fall back to the first screen.
        screen: {
            const name = Hyprland.focusedMonitor?.name
            return Quickshell.screens.find(s => s.name === name) || Quickshell.screens[0]
        }
        visible: scope.visible
        color: "transparent"
        implicitWidth: 520
        implicitHeight: 160
        anchors.bottom: true
        margins.bottom: 4
        exclusionMode: ExclusionMode.Normal
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "speakscope"
        mask: Region {}

        // Same accent as hyprbar (WallustPalette uses color4 of this file).
        FileView {
            id: palette
            property color accent: "#a9b7ff"
            path: (Quickshell.env("HOME") || "") + "/.cache/wallust/quickshell-hyprbar.json"
            watchChanges: true
            onFileChanged: reload()
            onLoaded: {
                try {
                    palette.accent = JSON.parse(text()).color4
                } catch (error) {}
            }
        }

        SpeakScope {
            id: scope
            anchors.fill: parent
            color: palette.accent
            feeding: root.active
            shown: root.state === "talking"
        }
    }
}
