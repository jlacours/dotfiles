import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Notif

Scope {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: popupWindow
      required property var modelData

      screen: modelData
      WlrLayershell.namespace: "quickshell-notif-" + (modelData ? modelData.name : "default")
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
      color: "transparent"
      exclusiveZone: 0
      visible: !Notif.NotificationServer.dnd && Notif.NotificationServer.popupQueue.count > 0
      implicitWidth: modelData.width
      implicitHeight: popupColumn.implicitHeight + 50
      mask: Region { item: popupColumn }

      anchors {
        top: true
        left: true
        right: true
      }

      margins {
        top: 28
      }

      Column {
        id: popupColumn
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: 360
        spacing: 8

        Repeater {
          model: Notif.NotificationServer.popupQueue

          Notif.NotificationItem {
            required property int notificationId
            required property int timestamp
            required property int stackTotal

            width: popupColumn.width
            compact: false
            stackCount: stackTotal
            notification: Notif.NotificationServer.notificationById(notificationId)
            createdAt: timestamp
            visible: notification !== null

            x: 0
            opacity: 1

            Behavior on x {
              NumberAnimation {
                duration: 200
                easing.type: Easing.OutQuad
              }
            }

            Behavior on opacity {
              NumberAnimation {
                duration: 150
                easing.type: Easing.OutQuad
              }
            }

            Component.onCompleted: {
              x = popupColumn.width
              opacity = 0
              Qt.callLater(function() {
                x = 0
                opacity = 1
              })
            }
          }
        }
      }
    }
  }
}
