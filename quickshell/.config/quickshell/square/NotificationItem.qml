import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications as Notifications
import "." as Square

Rectangle {
  id: root

  required property var notification
  required property int createdAt
  property bool compact: false
  property int stackCount: 1
  property bool hovered: hoverArea.containsMouse
  readonly property bool closeVisible: compact || hovered

  onHoveredChanged: {
    if (!root.compact && root.notification) {
      Square.NotificationState.setPopupHovered(root.notification.id, root.hovered)
    }
  }

  readonly property int progressValue: {
    const hints = root.notification && root.notification.hints ? root.notification.hints : null
    if (!hints) return -1
    const raw = hints["value"]
    if (raw === undefined || raw === null) return -1
    const parsed = Number(raw)
    if (isNaN(parsed)) return -1
    return Math.max(0, Math.min(100, Math.round(parsed)))
  }

  function sendReply() {
    if (!root.notification || !root.notification.hasInlineReply) return
    const text = (replyInput.text || "").trim()
    if (text === "") return
    root.notification.sendInlineReply(text)
    replyInput.text = ""
  }

  readonly property bool critical: notification && notification.urgency === Notifications.NotificationUrgency.Critical
  readonly property color accentColor: {
    if (!notification) return Theme.textDim
    switch (notification.urgency) {
    case Notifications.NotificationUrgency.Low:
      return Theme.textDim
    case Notifications.NotificationUrgency.Critical:
      return Theme.critical
    default:
      return Theme.accent
    }
  }

  function relativeTime() {
    const _tick = Square.NotificationState.timeRevision
    const elapsedSeconds = Math.max(0, Math.floor(Date.now() / 1000) - createdAt)

    if (elapsedSeconds < 45) return "now"
    if (elapsedSeconds < 3600) return Math.floor(elapsedSeconds / 60) + " min ago"
    if (elapsedSeconds < 86400) return Math.floor(elapsedSeconds / 3600) + " h ago"
    return Math.floor(elapsedSeconds / 86400) + " d ago"
  }

  function actionButtons() {
    if (!notification || !notification.actions) return []

    const actions = []

    for (let i = 0; i < notification.actions.length; i++) {
      const action = notification.actions[i]
      if (action.identifier !== "default") actions.push(action)
    }

    return actions
  }

  color: critical ? Theme.bg : Theme.surface
  border.width: Theme.hairline
  border.color: critical ? Theme.critical : Theme.border
  implicitWidth: compact ? 392 : 360
  implicitHeight: content.implicitHeight + Theme.padLg * 2
  height: implicitHeight

  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Theme.stripe
    color: root.accentColor
  }

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onClicked: {
      if (root.notification) {
        Square.NotificationState.invokeDefault(root.notification)
      }
    }
  }

  Row {
    id: content
    anchors.fill: parent
    anchors.margins: Theme.padLg
    anchors.leftMargin: Theme.stripe + Theme.padLg
    anchors.rightMargin: 28
    spacing: Theme.padMd

    Column {
      width: hasImage ? parent.width - 58 : parent.width
      spacing: Theme.padSm

      readonly property bool hasImage: root.notification && root.notification.image

      Item {
        width: parent.width
        height: 22

        Rectangle {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: 22
          height: 22
          color: "transparent"

          IconImage {
            anchors.fill: parent
            source: {
              const icon = root.notification && root.notification.appIcon ? root.notification.appIcon : ""
              return (icon.startsWith("/") ? "file://" : "") + icon
            }
            asynchronous: true
          }

          Text {
            anchors.centerIn: parent
            visible: !root.notification || !root.notification.appIcon
            text: "󰂚"
            color: Theme.textMuted
            font.family: Theme.iconFamily
            font.pixelSize: Theme.fontLg
          }
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 30
          anchors.right: stackBadge.left
          anchors.rightMargin: Theme.padMd
          anchors.verticalCenter: parent.verticalCenter
          text: root.notification ? (root.notification.appName || root.notification.desktopEntry || "APP") : "APP"
          elide: Text.ElideRight
          color: Theme.textMuted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSm
          font.bold: true
          font.letterSpacing: 0.6
        }

        Rectangle {
          id: stackBadge
          anchors.right: timeLabel.left
          anchors.rightMargin: Theme.padMd
          anchors.verticalCenter: parent.verticalCenter
          visible: root.stackCount > 1
          width: visible ? Math.max(20, stackLabel.implicitWidth + 10) : 0
          height: 15
          color: "transparent"
          border.width: Theme.hairline
          border.color: Theme.accent

          Text {
            id: stackLabel
            anchors.centerIn: parent
            text: "×" + root.stackCount
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSm
            font.bold: true
          }
        }

        Text {
          id: timeLabel
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.relativeTime()
          color: Theme.textDim
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSm
          horizontalAlignment: Text.AlignRight
        }
      }

      Text {
        width: parent.width
        text: root.notification ? root.notification.summary : ""
        elide: Text.ElideRight
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: root.compact ? Theme.fontSm : Theme.fontMd
        font.bold: true
      }

      Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.Wrap
        textFormat: Text.RichText
        text: root.notification ? (root.notification.body || "") : ""
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSm
      }

      Item {
        width: parent.width
        height: visible ? 14 : 0
        visible: root.progressValue >= 0

        Rectangle {
          anchors.left: parent.left
          anchors.right: progressPercent.left
          anchors.rightMargin: Theme.padMd
          anchors.verticalCenter: parent.verticalCenter
          height: 5
          color: Theme.bg
          border.width: Theme.hairline
          border.color: Theme.border

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * (root.progressValue / 100)
            color: root.critical ? Theme.critical : Theme.accent
          }
        }

        Text {
          id: progressPercent
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.progressValue + "%"
          color: Theme.textMuted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSm
        }
      }

      Row {
        visible: repeater.count > 0
        spacing: Theme.padMd

        Repeater {
          id: repeater
          model: root.actionButtons()

          Rectangle {
            required property var modelData

            width: Math.max(64, actionLabel.implicitWidth + 12)
            height: 22
            color: "transparent"
            border.width: Theme.hairline
            border.color: Theme.border

            Text {
              id: actionLabel
              anchors.centerIn: parent
              text: modelData.text
              color: Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSm
              font.bold: true
              font.letterSpacing: 0.5
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: modelData.invoke()
              onContainsMouseChanged: parent.border.color = containsMouse ? Theme.accent : Theme.border
            }
          }
        }
      }

      Item {
        width: parent.width
        height: visible ? 24 : 0
        visible: root.notification && root.notification.hasInlineReply

        Rectangle {
          id: replyField
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          anchors.right: replySend.left
          anchors.rightMargin: Theme.padMd
          height: 22
          color: Theme.bg
          border.width: Theme.hairline
          border.color: Theme.border

          TextInput {
            id: replyInput
            anchors.fill: parent
            anchors.leftMargin: Theme.padMd
            anchors.rightMargin: Theme.padMd
            anchors.verticalCenter: parent.verticalCenter
            verticalAlignment: Text.AlignVCenter
            clip: true
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSm
            activeFocusOnPress: true
            activeFocusOnTab: true

            Keys.onReturnPressed: root.sendReply()
            Keys.onEnterPressed: root.sendReply()
            Keys.onEscapePressed: {
              replyInput.text = ""
              replyInput.focus = false
            }
          }

          Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.padMd
            anchors.verticalCenter: parent.verticalCenter
            visible: replyInput.text === ""
            text: root.notification ? (root.notification.inlineReplyPlaceholder || "Reply…") : "Reply…"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSm
          }
        }

        Rectangle {
          id: replySend
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 44
          height: 22
          color: "transparent"
          border.width: Theme.hairline
          border.color: replySendArea.containsMouse ? Theme.accent : Theme.border

          Text {
            anchors.centerIn: parent
            text: "SEND"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSm
            font.bold: true
          }

          MouseArea {
            id: replySendArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sendReply()
          }
        }
      }
    }

    Image {
      width: 44
      height: 44
      visible: root.notification && root.notification.image
      source: {
        const icon = root.notification ? root.notification.image : ""
        return (icon.startsWith("/") ? "file://" : "") + icon
      }
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  Rectangle {
    id: closeButton
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: Theme.padSm
    anchors.rightMargin: Theme.padSm
    width: 16
    height: 16
    visible: root.closeVisible
    color: "transparent"
    border.width: Theme.hairline
    border.color: Theme.border

    Text {
      anchors.centerIn: parent
      text: "x"
      color: Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSm
      font.bold: true
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: Square.NotificationState.dismissOne(root.notification)
    }
  }
}
