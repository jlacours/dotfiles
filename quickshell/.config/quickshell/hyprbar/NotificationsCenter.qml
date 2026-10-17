import QtQuick 6.0
import Quickshell
import Quickshell.Hyprland

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
    anchor.rect.x: root.triggerItem.width - root.implicitWidth
    anchor.rect.y: root.below ? root.triggerItem.height + 4 : -root.implicitHeight - 4

    visible: root.shown || root.fadeOpacity > 0.01
    color: "transparent"
    implicitWidth: 380
    implicitHeight: Math.min(content.implicitHeight + 20, Math.min(480, root.panelWindow.screen.height - 40))

    onShownChanged: {
        fadeOpacity = shown ? 1 : 0
        if (shown) {
            scroll.contentY = 0
        }
    }

    Behavior on fadeOpacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
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

        Column {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 8

            // Header row
            Item {
                width: parent.width
                height: 18

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "NOTIFICATIONS · " + NotificationsState.history.count
                    color: root.accentColor
                    font.family: "Comic Code"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    // DND toggle button
                    Rectangle {
                        width: dndLabel.implicitWidth + 10
                        height: 18
                        color: NotificationsState.dnd ? root.accentColor : "transparent"
                        border.width: 1
                        border.color: NotificationsState.dnd ? root.accentColor : root.mutedColor

                        Text {
                            id: dndLabel
                            anchors.centerIn: parent
                            text: NotificationsState.dnd ? "DND ON" : "DND OFF"
                            color: NotificationsState.dnd ? root.backgroundColor : root.mutedColor
                            font.family: "Comic Code"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationsState.toggleDnd()
                        }
                    }

                    // Clear All button
                    Rectangle {
                        visible: NotificationsState.history.count > 0
                        width: clearLabel.implicitWidth + 10
                        height: 18
                        color: clearArea.containsMouse ? root.accentColor : "transparent"
                        border.width: 1
                        border.color: clearArea.containsMouse ? root.accentColor : root.mutedColor

                        Text {
                            id: clearLabel
                            anchors.centerIn: parent
                            text: "CLEAR ALL"
                            color: clearArea.containsMouse ? root.backgroundColor : root.mutedColor
                            font.family: "Comic Code"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        MouseArea {
                            id: clearArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationsState.clearHistory()
                        }
                    }

                    // Close (X)
                    Text {
                        text: "×"
                        color: root.mutedColor
                        font.family: "Comic Code"
                        font.pixelSize: 12

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.shown = false
                        }
                    }
                }
            }

            // Separator
            Rectangle {
                width: parent.width
                height: 1
                color: root.mutedColor
                opacity: 0.25
            }

            // Scrollable list
            Flickable {
                id: scroll
                width: parent.width
                height: Math.min(itemsList.implicitHeight, 380)
                clip: true
                contentWidth: width
                contentHeight: itemsList.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: itemsList
                    width: scroll.width
                    spacing: 6

                    // Empty state
                    Item {
                        width: parent.width
                        height: 60
                        visible: NotificationsState.history.count === 0

                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰂚"
                                color: root.mutedColor
                                font.family: "Comic Code"
                                font.pixelSize: 18
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "No notifications"
                                color: root.mutedColor
                                font.family: "Comic Code"
                                font.pixelSize: 11
                            }
                        }
                    }

                    Repeater {
                        model: NotificationsState.history

                        NotificationsItem {
                            required property int notificationId
                            required property int timestamp

                            width: itemsList.width
                            notification: NotificationsState.notificationById(notificationId)
                            createdAt: timestamp
                            isPopup: false
                            visible: notification !== null
                        }
                    }
                }
            }
        }
    }
}
