import Quickshell
import Quickshell.Hyprland
import QtQuick 6.0

PopupWindow {
    id: root

    required property var panelWindow
    required property var triggerItem
    required property bool below
    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor
    property bool shown: false
    property real fadeOpacity: 0

    anchor.window: root.panelWindow
    anchor.item: root.triggerItem
    anchor.rect.x: Math.round((root.triggerItem.width - root.implicitWidth) / 2)
    anchor.rect.y: root.below ? root.triggerItem.height + 4 : -root.implicitHeight - 4
    visible: root.shown || root.fadeOpacity > 0.01
    color: "transparent"
    implicitWidth: 380
    implicitHeight: Math.min(content.implicitHeight + 20, Math.min(480, root.panelWindow.screen.height - 40))

    onShownChanged: {
        fadeOpacity = shown ? 1 : 0
        if (shown) {
            TodoState.refresh()
            scroll.contentY = 0
        }
    }

    Behavior on fadeOpacity {
        NumberAnimation { duration: 380; easing.type: Easing.OutCubic }
    }

    HyprlandFocusGrab {
        active: root.shown && root.backingWindowVisible
        windows: [root]
        onCleared: root.shown = false
    }

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
        border.color: root.foregroundColor
        border.width: 1
        opacity: root.fadeOpacity

        Flickable {
            id: scroll
            anchors.fill: parent
            anchors.margins: 10
            clip: true
            contentWidth: width
            contentHeight: content.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: content
                width: scroll.width
                spacing: 7

                Item {
                    width: parent.width
                    height: 16

                    Text {
                        text: "TODOS · " + (TodoState.available ? TodoState.count : "?")
                        color: root.accentColor
                        font.family: "Comic Code"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Text {
                        anchors.right: parent.right
                        text: "×"
                        color: root.mutedColor
                        font.family: "Comic Code"
                        font.pixelSize: 12

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -5
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shown = false
                        }
                    }
                }

                Text {
                    visible: !TodoState.available || TodoState.count === 0
                    text: TodoState.available ? "No open todos" : "Todos unavailable"
                    color: root.mutedColor
                    font.family: "Comic Code"
                    font.pixelSize: 11
                }

                Repeater {
                    model: TodoState.groups

                    delegate: Column {
                        id: group
                        required property var modelData
                        width: content.width
                        spacing: 5

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Qt.alpha(root.foregroundColor, 0.16)
                        }

                        Text {
                            text: group.modelData.name + " · " + group.modelData.items.length
                            color: root.accentColor
                            font.family: "Comic Code"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        Repeater {
                            model: group.modelData.items

                            delegate: Column {
                                id: todoRow
                                required property var modelData
                                width: group.width
                                spacing: 2

                                Text {
                                    width: parent.width
                                    text: todoRow.modelData.summary
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                    color: root.foregroundColor
                                    font.family: "Comic Code"
                                    font.pixelSize: 11
                                }

                                Text {
                                    visible: todoRow.modelData.due !== null
                                    text: todoRow.modelData.due === null ? "" :
                                        (TodoState.overdue(todoRow.modelData) ? "overdue · " : "due · ")
                                        + Qt.formatDateTime(new Date(todoRow.modelData.due * 1000), "ddd MMM d, yyyy HH:mm")
                                    color: TodoState.overdue(todoRow.modelData) ? root.accentColor : root.mutedColor
                                    font.family: "Comic Code"
                                    font.pixelSize: 9
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
