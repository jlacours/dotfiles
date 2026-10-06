import QtQuick 6.0

// Read-only todo count; all polling is shared between monitors.
BarChip {
    id: root

    implicitWidth: Math.max(23, label.implicitWidth + 10)
    tooltipText: TodoState.tooltip
    onClicked: todoPanel.shown = !todoPanel.shown

    Text {
        id: label
        anchors.centerIn: parent
        text: "☷ " + (TodoState.available ? TodoState.count : "?")
        color: !TodoState.available || TodoState.count === 0 ? root.mutedColor
            : TodoState.attention ? root.accentColor : root.foregroundColor
        font.family: "Comic Code"
        font.pixelSize: 11
        font.weight: Font.Medium
    }

    TodoPanel {
        id: todoPanel
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
        mutedColor: root.mutedColor
        accentColor: root.accentColor
    }
}
