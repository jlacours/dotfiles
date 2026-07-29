import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
  PanelWindow {
    id: popupWindow

    readonly property var targetScreen: {
      const active = ToplevelManager.activeToplevel;
      if (active && active.screens && active.screens.length > 0)
        return active.screens[0];
      return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    screen: targetScreen
    visible: NotificationState.popupQueue.count > 0
    color: "transparent"
    exclusiveZone: 0
    implicitWidth: 360
    implicitHeight: popupColumn.implicitHeight + 16

    WlrLayershell.namespace: "quickshell-win95-notifications"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      bottom: true
      right: true
    }

    margins {
      bottom: 16
      right: 8
    }

    mask: Region { item: popupColumn }

    Column {
      id: popupColumn
      anchors {
        right: parent.right
        bottom: parent.bottom
      }
      width: 340
      spacing: 6

      Repeater {
        model: NotificationState.popupQueue

        NotificationPopup {
          required property int notificationId
          width: popupColumn.width
          notification: NotificationState.notificationById(notificationId)
          visible: notification !== null
        }
      }
    }
  }
}
