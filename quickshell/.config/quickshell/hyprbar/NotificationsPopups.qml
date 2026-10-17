import QtQuick 6.0
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: popupWindow
                required property var modelData

                screen: modelData

                readonly property bool isFocused: {
                    const focused = Hyprland.focusedMonitor
                        || Hyprland.monitors.values.find(m => m.focused)
                    if (focused)
                        return focused.name === modelData.name
                    return modelData.name === "HDMI-A-1"
                }

                readonly property bool shouldShow: isFocused
                    && (!NotificationsState.dnd || NotificationsState.criticalCount > 0)
                    && NotificationsState.popupQueue.count > 0

                visible: shouldShow
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.namespace: "quickshell-notifications"
                // None, not OnDemand: popups are display-only (clicks still
                // work). OnDemand makes Hyprland give this Overlay surface
                // the seat's keyboard focus when it maps, so keystrokes stop
                // reaching the focused toplevel until the popup expires.
                // Inline reply stays usable in NotificationsCenter, which
                // takes an explicit HyprlandFocusGrab when opened.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

                anchors {
                    top: true
                    right: true
                }

                margins {
                    top: modelData.name === "DP-1" ? 10 : 32
                    right: 14
                }

                implicitWidth: 380
                implicitHeight: popupColumn.implicitHeight + 10

                Column {
                    id: popupColumn
                    width: 380
                    spacing: 8

                    Repeater {
                        model: NotificationsState.popupQueue

                        NotificationsItem {
                            required property int notificationId
                            required property int timestamp
                            required property int stackTotal

                            width: popupColumn.width
                            notification: NotificationsState.notificationById(notificationId)
                            createdAt: timestamp
                            stackCount: stackTotal
                            isPopup: true
                            visible: notification !== null
                        }
                    }
                }
            }
        }
    }
}
