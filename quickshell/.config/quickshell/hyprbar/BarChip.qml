import QtQuick 6.0

// Shared 23x22 indicator cell: hover fill, click action and tooltip. Colors
// and tooltip placement default to the owning Bar; children are the icon.
Rectangle {
    id: root

    required property var panelWindow
    property color backgroundColor: panelWindow.background
    property color foregroundColor: panelWindow.foreground
    property color mutedColor: panelWindow.muted
    property color accentColor: panelWindow.accent
    property color hoverColor: panelWindow.surfaceHover
    property bool tooltipBelow: !panelWindow.isTopMonitor
    property string tooltipText: ""
    property alias clickEnabled: chipMouse.enabled
    property alias cursorShape: chipMouse.cursorShape
    // Defaults to left button only; chips that need right-click set this to
    // Qt.LeftButton | Qt.RightButton and listen to rightClicked().
    property alias acceptedButtons: chipMouse.acceptedButtons

    signal clicked()
    signal rightClicked()

    implicitWidth: 23
    implicitHeight: 22
    radius: 0
    color: chipMouse.containsMouse ? root.hoverColor : "transparent"

    MouseArea {
        id: chipMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked()
            else
                root.clicked()
        }
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: chipMouse.containsMouse
        labelText: root.tooltipText
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
