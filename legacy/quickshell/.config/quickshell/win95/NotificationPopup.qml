import QtQuick
import Quickshell
import Quickshell.Widgets

BevelRect {
  id: root

  required property var notification

  width: 340
  height: Math.max(88, titleBar.height + messageColumn.implicitHeight + 24)

  Rectangle {
    id: titleBar
    anchors {
      top: parent.top
      left: parent.left
      right: parent.right
      margins: 3
    }
    height: 22
    color: Win95Theme.highlight

    Text {
      anchors {
        left: parent.left
        right: closeButton.left
        leftMargin: 6
        rightMargin: 6
        verticalCenter: parent.verticalCenter
      }
      text: root.notification
        ? (root.notification.appName || root.notification.desktopEntry || "Notification")
        : "Notification"
      color: Win95Theme.highlightText
      elide: Text.ElideRight
      font.family: "Comic Code"
      font.pixelSize: 11
      font.bold: true
    }

    Win95CloseButton {
      id: closeButton
      anchors {
        right: parent.right
        rightMargin: 2
        verticalCenter: parent.verticalCenter
      }
      onClicked: {
        if (root.notification)
          NotificationState.dismiss(root.notification.id);
      }
    }
  }

  Item {
    anchors {
      top: titleBar.bottom
      left: parent.left
      right: parent.right
      bottom: parent.bottom
      margins: 10
      topMargin: 8
    }

    IconImage {
      id: notificationIcon
      anchors {
        left: parent.left
        top: parent.top
      }
      implicitSize: 32
      source: {
        const icon = root.notification && root.notification.appIcon
          ? root.notification.appIcon
          : "dialog-information";
        if (icon.startsWith("/"))
          return "file://" + icon;
        if (icon.includes(":"))
          return icon;
        return Quickshell.iconPath(icon, true);
      }
      asynchronous: true
    }

    Column {
      id: messageColumn
      anchors {
        top: parent.top
        left: notificationIcon.right
        right: parent.right
        leftMargin: 10
      }
      spacing: 4

      Text {
        width: parent.width
        text: root.notification ? (root.notification.summary || "Notification") : "Notification"
        color: Win95Theme.text
        elide: Text.ElideRight
        font.family: "Comic Code"
        font.pixelSize: 11
        font.bold: true
      }

      Text {
        width: parent.width
        visible: text !== ""
        text: root.notification ? (root.notification.body || "") : ""
        color: Win95Theme.text
        wrapMode: Text.Wrap
        maximumLineCount: 4
        elide: Text.ElideRight
        textFormat: Text.PlainText
        font.family: "Comic Code"
        font.pixelSize: 10
      }
    }
  }
}
