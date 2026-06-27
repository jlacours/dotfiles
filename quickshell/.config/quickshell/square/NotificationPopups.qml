import QtQuick
import Quickshell
import Quickshell.Wayland
import "." as Square

Scope {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: popupWindow
      required property var modelData

      screen: modelData
      WlrLayershell.namespace: "quickshell-square-notifications-" + (modelData ? modelData.name : "default")
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      color: "transparent"
      exclusiveZone: 0
      visible: !Square.NotificationState.dnd && Square.NotificationState.popupQueue.count > 0
      implicitWidth: 380
      implicitHeight: popupColumn.implicitHeight + Theme.padLg * 2
      mask: Region { item: popupColumn }

      anchors {
        top: true
        right: true
      }

      margins {
        top: Theme.barHeight + Theme.padMd
        right: Theme.padMd
      }

      Column {
        id: popupColumn
        anchors.top: parent.top
        anchors.right: parent.right
        width: 360
        spacing: Theme.padSm

        Repeater {
          model: Square.NotificationState.popupQueue

          Square.NotificationItem {
            required property int notificationId
            required property int timestamp
            required property int stackTotal

            width: popupColumn.width
            compact: false
            stackCount: stackTotal
            notification: Square.NotificationState.notificationById(notificationId)
            createdAt: timestamp
            visible: notification !== null
          }
        }
      }
    }
  }
}
