import Quickshell
import QtQuick 6.0

BarChip {
    id: root
    implicitWidth: label.implicitWidth + 10
    tooltipText: "Jobs working / needing report / findings\n" + AgentsState.tooltip
    onClicked: Quickshell.execDetached(["foot", "--app-id=workflow-status", "--title=Workflow status", "--hold", "sh", "-c", "$HOME/.local/bin/agent-board --plain"])
    Text {
        id: label
        anchors.centerIn: parent
        text: "≡ " + AgentsState.text
        color: AgentsState.state === "warning" || AgentsState.state === "unknown"
            ? root.accentColor : AgentsState.state === "working" ? root.foregroundColor : root.mutedColor
        font.family: "Comic Code"
        font.pixelSize: 11
    }
}
