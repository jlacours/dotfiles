pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick 6.0

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string scriptPath: home + "/.config/quickshell/hyprbar/system-vitals.sh"
    property int cpu: 0
    property int ram: 0
    property int disk: 0
    property int temp: 0
    property int gpu: -1
    property int gpuTemp: -1

    function refresh() {
        if (!statusProcess.running)
            statusProcess.exec([root.scriptPath])
    }

    function parseStatus(value) {
        try {
            const result = JSON.parse(value.trim())
            root.cpu = Number(result.cpu) || 0
            root.ram = Number(result.ram) || 0
            root.disk = Number(result.disk) || 0
            root.temp = Number(result.temp) || 0
            root.gpu = Number(result.gpu)
            root.gpuTemp = Number(result.gpuTemp)
        } catch (error) {
            console.warn("Could not parse system vitals:", error)
        }
    }

    Component.onCompleted: refresh()

    Process {
        id: statusProcess

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseStatus(text)
        }
    }

    Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
