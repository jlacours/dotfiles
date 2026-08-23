import Quickshell
import QtQuick 6.0

PopupWindow {
    id: root

    required property var panelWindow
    required property var triggerItem
    required property bool below
    required property bool shown
    required property string labelText
    required property color backgroundColor
    required property color foregroundColor

    anchor.window: root.panelWindow
    anchor.item: root.triggerItem
    anchor.rect.x: Math.round((root.triggerItem.width - root.implicitWidth) / 2)
    anchor.rect.y: root.below ? root.triggerItem.height + 4 : -root.implicitHeight - 4

    visible: root.shown
    color: "transparent"
    implicitWidth: tooltipText.implicitWidth + 14
    implicitHeight: tooltipText.implicitHeight + 8

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
        border.color: root.foregroundColor
        border.width: 1

        Text {
            id: tooltipText
            anchors.centerIn: parent
            text: root.labelText
            color: root.foregroundColor
            font.family: "monospace"
            font.pixelSize: 12
            font.weight: Font.Medium
            elide: Text.ElideNone
            wrapMode: Text.NoWrap
        }
    }
}
