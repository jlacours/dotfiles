import QtQuick 6.0
import Quickshell.Hyprland

BarChip {
    id: root

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: Math.max(23, chipContent.implicitWidth + 12)

    tooltipText: {
        let text = NotificationsState.dnd
            ? "Notifications: DND active"
            : ("Notifications: " + NotificationsState.unreadCount + " unread"
                + (NotificationsState.criticalCount > 0 ? (" (" + NotificationsState.criticalCount + " critical)") : ""))
        text += "\nLeft click: notification centre · Right click: "
            + (NotificationsState.dnd ? "disable DND" : "enable DND")
        return text
    }

    onClicked: centerPanel.shown = !centerPanel.shown
    onRightClicked: NotificationsState.toggleDnd()

    Connections {
        target: NotificationsState
        function onCenterToggled() {
            const focusedMonitor = Hyprland.focusedMonitor
            const hyprMon = root.panelWindow.hyprMonitor
            const isFocused = (hyprMon && hyprMon.focused)
                || (focusedMonitor && focusedMonitor.name === root.panelWindow.monitorName)
            if (isFocused) {
                centerPanel.shown = !centerPanel.shown
            }
        }
    }

    Row {
        id: chipContent
        anchors.centerIn: parent
        spacing: 4

        Text {
            id: iconText
            anchors.verticalCenter: parent.verticalCenter
            text: NotificationsState.dnd ? "󰂛" : "󰂚"
            color: NotificationsState.dnd
                ? root.mutedColor
                : (NotificationsState.criticalCount > 0
                    ? "#E08A86"
                    : (NotificationsState.unreadCount > 0 ? root.accentColor : root.foregroundColor))
            font.family: "Comic Code"
            font.pixelSize: 11
        }

        Text {
            id: countText
            anchors.verticalCenter: parent.verticalCenter
            visible: NotificationsState.unreadCount > 0 && !NotificationsState.dnd
            text: NotificationsState.unreadCount
            color: NotificationsState.criticalCount > 0 ? "#E08A86" : root.accentColor
            font.family: "Comic Code"
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
    }

    NotificationsCenter {
        id: centerPanel
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
        mutedColor: root.mutedColor
        accentColor: root.accentColor
    }
}
