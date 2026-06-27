import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications as Notify
import "." as Square

Scope {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: centerWindow
      required property var modelData
      readonly property bool activeScreen: Square.NotificationState.centerScreenName === modelData.name

      screen: modelData
      WlrLayershell.namespace: "quickshell-square-notification-center-" + (modelData ? modelData.name : "default")
      WlrLayershell.layer: WlrLayer.Overlay
      color: "transparent"
      exclusiveZone: 0
      visible: Square.NotificationState.centerVisible && activeScreen
      implicitWidth: 380
      implicitHeight: panel.height
      mask: Region { item: panel }

      anchors {
        top: true
        right: true
      }

      margins {
        top: Theme.barHeight + Theme.padMd
        right: Theme.padMd
      }

      Rectangle {
        id: panel
        width: 380
        height: Math.min(modelData.height - Theme.barHeight - Theme.padLg * 2, 430)
        anchors.top: parent.top
        anchors.right: parent.right
        color: Theme.surface
        border.width: Theme.hairline
        border.color: Theme.border

        Column {
          anchors.fill: parent
          anchors.margins: Theme.padMd
          spacing: Theme.padMd

          Row {
            width: parent.width
            spacing: Theme.padMd

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "NOTIFICATIONS"
              color: Theme.textMuted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSm
              font.bold: true
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: String(Square.NotificationState.unreadCount)
              color: Square.NotificationState.criticalCount > 0 ? Theme.critical : Theme.text
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontMd
              font.bold: true
            }

            Item {
              width: 1
              height: 1
              LayoutMirroring.enabled: false
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Square.NotificationState.dnd ? "DND ON" : "DND OFF"
              color: Square.NotificationState.dnd ? Theme.critical : Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSm
              font.bold: true

              MouseArea {
                anchors.fill: parent
                anchors.margins: -Theme.padSm
                cursorShape: Qt.PointingHandCursor
                onClicked: Square.NotificationState.toggleDnd()
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "CLEAR"
              color: clearArea.containsMouse ? Theme.text : Theme.textDim
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSm
              font.bold: true

              MouseArea {
                id: clearArea
                anchors.fill: parent
                anchors.margins: -Theme.padSm
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Square.NotificationState.clearAll()
              }
            }
          }

          Rectangle {
            width: parent.width
            height: Theme.hairline
            color: Theme.border
          }

          Item {
            width: parent.width
            height: parent.height - y

            ListView {
              id: list
              anchors.fill: parent
              clip: true
              spacing: Theme.padSm
              model: Square.NotificationState.history
              visible: count > 0

              delegate: Square.NotificationItem {
                required property int notificationId
                required property int timestamp

                width: list.width
                compact: true
                notification: Square.NotificationState.notificationById(notificationId)
                createdAt: timestamp
                visible: notification !== null
              }
            }

            Column {
              anchors.centerIn: parent
              spacing: Theme.padSm
              visible: !list.visible

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "N"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontLg
                font.bold: true
              }

              Text {
                text: "NO NOTIFICATIONS"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSm
                font.bold: true
              }
            }
          }
        }
      }
    }
  }
}
