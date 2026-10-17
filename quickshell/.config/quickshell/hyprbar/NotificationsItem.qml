import QtQuick 6.0
import QtQuick.Layouts 6.0
import Quickshell
import Quickshell.Widgets

Rectangle {
    id: root

    required property var notification
    required property int createdAt
    property int stackCount: 1
    property bool isPopup: false
    readonly property bool hovered: cardMouse.containsMouse

    WallustPalette {
        id: palette
    }

    readonly property color criticalColor: "#E08A86"
    readonly property color accentColor: palette.accent
    readonly property color mutedColor: palette.muted
    readonly property color foregroundColor: palette.foreground
    readonly property color surfaceColor: palette.surface
    readonly property color surfaceHoverColor: palette.surfaceHover
    readonly property color borderColor: palette.border

    readonly property int urgency: NotificationsState.urgencyValue(root.notification)
    readonly property bool critical: root.urgency === 2

    onHoveredChanged: {
        if (root.isPopup && root.notification) {
            NotificationsState.setPopupHovered(root.notification.id, root.hovered)
        }
    }

    readonly property int progressValue: {
        const hints = root.notification && root.notification.hints ? root.notification.hints : null
        if (hints && hints["value"] !== undefined && hints["value"] !== null) {
            const parsed = Number(hints["value"])
            if (!isNaN(parsed))
                return Math.max(0, Math.min(100, Math.round(parsed)))
        }
        const textToCheck = (root.notification ? (root.notification.body || root.notification.summary || "") : "").trim()
        const match = textToCheck.match(/^(\d{1,3})%$/)
        if (match) {
            return Math.max(0, Math.min(100, parseInt(match[1], 10)))
        }
        return -1
    }

    function relativeTime() {
        const _tick = NotificationsState.timeRevision
        const elapsed = Math.max(0, Math.floor(Date.now() / 1000) - createdAt)
        if (elapsed < 45)
            return "now"
        if (elapsed < 3600)
            return Math.floor(elapsed / 60) + "m ago"
        if (elapsed < 86400)
            return Math.floor(elapsed / 3600) + "h ago"
        return Math.floor(elapsed / 86400) + "d ago"
    }

    function resolveIcon(raw) {
        if (!raw)
            return ""
        if (raw.startsWith("/") || raw.startsWith("file://"))
            return (raw.startsWith("/") ? "file://" : "") + raw
        if (Quickshell.hasThemeIcon(raw))
            return Quickshell.iconPath(raw)
        return ""
    }

    function actionButtons() {
        if (!notification || !notification.actions)
            return []
        const list = []
        for (let i = 0; i < notification.actions.length; i++) {
            const act = notification.actions[i]
            if (act.identifier !== "default")
                list.push(act)
        }
        return list
    }

    function sendReply() {
        if (!root.notification || !root.notification.hasInlineReply)
            return
        const text = (replyInput.text || "").trim()
        if (!text)
            return
        root.notification.sendInlineReply(text)
        replyInput.text = ""
        if (root.isPopup)
            NotificationsState.dismissPopup(root.notification.id)
    }

    color: root.surfaceColor
    border.width: 1
    border.color: root.critical ? root.criticalColor : (root.hovered ? root.accentColor : root.borderColor)
    implicitHeight: col.implicitHeight + 16

    // Urgency left stripe
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 3
        color: root.critical ? root.criticalColor : (root.urgency === 0 ? root.mutedColor : root.accentColor)
    }

    // Card background click for default action
    MouseArea {
        id: cardMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.notification && NotificationsState.defaultAction(root.notification)
            ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.notification)
                NotificationsState.invokeDefault(root.notification)
        }
    }

    Column {
        id: col
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 12
            rightMargin: 10
            topMargin: 8
        }
        spacing: 5

        // Header
        Item {
            width: parent.width
            height: 18

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Item {
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: appIconImg
                        anchors.fill: parent
                        source: root.resolveIcon(root.notification
                            ? (root.notification.appIcon || root.notification.desktopEntry || "")
                            : "")
                        fillMode: Image.PreserveAspectFit
                        sourceSize.width: 16
                        sourceSize.height: 16
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: !appIconImg.visible
                        text: "󰂚"
                        color: root.mutedColor
                        font.family: "Comic Code"
                        font.pixelSize: 11
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.notification
                        ? (root.notification.appName || root.notification.desktopEntry || "SYSTEM").toUpperCase()
                        : "SYSTEM"
                    color: root.mutedColor
                    font.family: "Comic Code"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.stackCount > 1
                    width: stackText.implicitWidth + 6
                    height: 14
                    color: "transparent"
                    border.width: 1
                    border.color: root.accentColor

                    Text {
                        id: stackText
                        anchors.centerIn: parent
                        text: "×" + root.stackCount
                        color: root.accentColor
                        font.family: "Comic Code"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.relativeTime()
                    color: root.mutedColor
                    font.family: "Comic Code"
                    font.pixelSize: 10
                }

                Rectangle {
                    width: 16
                    height: 16
                    color: closeMouse.containsMouse ? root.surfaceHoverColor : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "×"
                        color: closeMouse.containsMouse ? root.foregroundColor : root.mutedColor
                        font.family: "Comic Code"
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!root.notification)
                                return
                            if (root.isPopup)
                                NotificationsState.dismissPopup(root.notification.id)
                            else
                                NotificationsState.dismissOne(root.notification.id)
                        }
                    }
                }
            }
        }

        // Summary
        Text {
            width: parent.width
            visible: text !== ""
            text: root.notification ? (root.notification.summary || "") : ""
            color: root.foregroundColor
            font.family: "Comic Code"
            font.pixelSize: 11
            font.weight: Font.Bold
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }

        // Body
        Text {
            width: parent.width
            visible: text !== ""
            textFormat: Text.StyledText
            text: root.notification ? (root.notification.body || "") : ""
            color: root.mutedColor
            font.family: "Comic Code"
            font.pixelSize: 10
            lineHeight: 1.15
            wrapMode: Text.Wrap
            onLinkActivated: link => Qt.openUrlExternally(link)
        }

        // Progress bar (volume, downloads, etc.)
        Item {
            width: parent.width
            height: 12
            visible: root.progressValue >= 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: progText.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 4
                color: root.surfaceHoverColor

                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * (root.progressValue / 100)
                    color: root.critical ? root.criticalColor : root.accentColor
                }
            }

            Text {
                id: progText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.progressValue + "%"
                color: root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 10
            }
        }

        // Image attachment
        Image {
            id: attachmentImage
            width: Math.min(parent.width, 240)
            height: Math.min(100, implicitHeight)
            visible: (root.notification && root.notification.image !== "") && status === Image.Ready
            source: {
                const img = root.notification ? root.notification.image : ""
                return root.resolveIcon(img)
            }
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }

        // Actions
        Row {
            id: actionsRow
            visible: actRepeater.count > 0
            spacing: 6

            Repeater {
                id: actRepeater
                model: root.actionButtons()

                Rectangle {
                    required property var modelData

                    width: actLabel.implicitWidth + 14
                    height: 20
                    color: actMouse.containsMouse ? root.surfaceHoverColor : "transparent"
                    border.width: 1
                    border.color: actMouse.containsMouse ? root.accentColor : root.borderColor

                    Text {
                        id: actLabel
                        anchors.centerIn: parent
                        text: modelData.text
                        color: actMouse.containsMouse ? root.accentColor : root.foregroundColor
                        font.family: "Comic Code"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: actMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotificationsState.invokeAction(root.notification, modelData)
                    }
                }
            }
        }

        // Inline reply
        Item {
            width: parent.width
            height: 22
            visible: root.notification && root.notification.hasInlineReply

            Rectangle {
                anchors.left: parent.left
                anchors.right: sendBtn.left
                anchors.rightMargin: 6
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                color: root.surfaceHoverColor
                border.width: 1
                border.color: replyInput.activeFocus ? root.accentColor : root.borderColor

                TextInput {
                    id: replyInput
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    verticalAlignment: Text.AlignVCenter
                    clip: true
                    color: root.foregroundColor
                    font.family: "Comic Code"
                    font.pixelSize: 10

                    Keys.onReturnPressed: root.sendReply()
                    Keys.onEnterPressed: root.sendReply()
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    visible: replyInput.text === ""
                    text: root.notification ? (root.notification.inlineReplyPlaceholder || "Reply…") : "Reply…"
                    color: root.mutedColor
                    font.family: "Comic Code"
                    font.pixelSize: 10
                }
            }

            Rectangle {
                id: sendBtn
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 44
                color: sendMouse.containsMouse ? root.surfaceHoverColor : "transparent"
                border.width: 1
                border.color: sendMouse.containsMouse ? root.accentColor : root.borderColor

                Text {
                    anchors.centerIn: parent
                    text: "SEND"
                    color: sendMouse.containsMouse ? root.accentColor : root.foregroundColor
                    font.family: "Comic Code"
                    font.pixelSize: 9
                    font.weight: Font.Bold
                }

                MouseArea {
                    id: sendMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sendReply()
                }
            }
        }
    }
}
