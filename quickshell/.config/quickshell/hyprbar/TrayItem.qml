import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick 6.0

Rectangle {
    id: root

    required property var item
    required property color hoverColor

    implicitWidth: 24
    implicitHeight: 24
    color: trayMouse.containsMouse || menuAnchor.visible ? root.hoverColor : "transparent"

    IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: {
            const icon = root.item.icon || ""
            return (icon.startsWith("/") ? "file://" : "") + icon
        }
        asynchronous: true
    }

    QsMenuAnchor {
        id: menuAnchor
        menu: root.item.menu
        anchor.item: root
        // Keep right-edge tray menus under their icon instead of centering them.
        anchor.edges: Edges.Bottom | Edges.Right
        anchor.gravity: Edges.Bottom | Edges.Left
    }

    MouseArea {
        id: trayMouse

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton) {
                if (root.item.onlyMenu && root.item.hasMenu)
                    menuAnchor.open()
                else
                    root.item.activate()
                return
            }

            if (mouse.button === Qt.MiddleButton) {
                root.item.secondaryActivate()
                return
            }

            if (root.item.hasMenu)
                menuAnchor.open()
        }
    }
}
