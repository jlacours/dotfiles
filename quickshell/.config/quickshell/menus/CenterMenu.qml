import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "." as Menus
import "../wallust.js" as Wallust

// Centered, wide (NOT fullscreen) menu overlay — the quickshell replacement
// for every rofi menu. One instance per screen (Variants, like
// clipboard/ClipboardHistory.qml); MenuState.screenName picks which one is
// live. Populated by MenuState.show*() and driven by the "menu" IpcHandler
// below, which qs-dmenu.sh and the Hyprland binds (hyprland.conf) call via
// scripts/qs-ipc.sh.
//
// Styling note: imports wallust.js directly (like clipboard/keybinds), not
// square/Theme.qml — see MenuItem.qml's header comment for why (a
// Quickshell-specific pragma-Singleton cross-directory registry risk, found
// via deepwiki, not just a stylistic choice). Non-palette constants (font,
// spacing, hairline, animation duration) are literal copies of
// square/Theme.qml's current values.
Scope {
  id: root

  readonly property color bgBase: Wallust.bg
  readonly property color surfaceBase: Wallust.surfaceElevated
  readonly property color borderBase: Wallust.border
  readonly property color panelSurface: Qt.rgba(bgBase.r, bgBase.g, bgBase.b, 0.90)
  readonly property color cardSurface: Qt.rgba(surfaceBase.r, surfaceBase.g, surfaceBase.b, 0.64)
  readonly property color borderSubtle: Qt.rgba(borderBase.r, borderBase.g, borderBase.b, 0.48)

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: menuWindow
      required property var modelData

      screen: modelData
      color: "transparent"
      exclusiveZone: 0
      readonly property bool activeScreen: Menus.MenuState.screenName === modelData.name
      readonly property bool overlayVisible: Menus.MenuState.visible && activeScreen

      visible: overlayVisible || fadeAnim.running
      WlrLayershell.keyboardFocus: overlayVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      // Wide, dead-centered — the whole point of this component versus the
      // old rofi theme (juju-default.rasi, fullscreen: true).
      readonly property int panelWidth: Math.max(480, Math.min(920, Math.round(modelData.width * 0.55)))
      readonly property int minPanelHeight: 220
      readonly property int maxPanelHeight: Math.max(minPanelHeight, Math.round(modelData.height * 0.6))
      readonly property int desiredPanelHeight: headerRow.implicitHeight + filterBox.height + 56
        + (menuList.visible ? Math.min(menuList.contentHeight, maxPanelHeight) : emptyState.implicitHeight + 24)

      Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: menuWindow.overlayVisible
        onActivated: {
          if (filterInput.text !== "") filterInput.text = ""
          else Menus.MenuState.cancelCurrent()
        }
      }

      Shortcut {
        sequence: "Down"
        context: Qt.WindowShortcut
        enabled: menuWindow.overlayVisible && menuList.count > 0
        onActivated: menuWindow.moveSelection(1)
      }

      Shortcut {
        sequence: "Up"
        context: Qt.WindowShortcut
        enabled: menuWindow.overlayVisible && menuList.count > 0
        onActivated: menuWindow.moveSelection(-1)
      }

      Shortcut {
        sequence: "Return"
        context: Qt.WindowShortcut
        enabled: menuWindow.overlayVisible
        onActivated: Menus.MenuState.activateCurrent(menuList.currentIndex)
      }

      Shortcut {
        sequence: "Enter"
        context: Qt.WindowShortcut
        enabled: menuWindow.overlayVisible
        onActivated: Menus.MenuState.activateCurrent(menuList.currentIndex)
      }

      MouseArea {
        anchors.fill: parent
        visible: menuWindow.overlayVisible
        onClicked: Menus.MenuState.cancelCurrent()
      }

      Rectangle {
        id: panel

        width: menuWindow.panelWidth
        height: Math.min(menuWindow.maxPanelHeight, Math.max(menuWindow.minPanelHeight, menuWindow.desiredPanelHeight))
        anchors.centerIn: parent
        color: root.panelSurface
        border.width: 1
        border.color: root.borderSubtle

        opacity: menuWindow.overlayVisible ? 1 : 0
        scale: menuWindow.overlayVisible ? 1 : 0.96

        Behavior on opacity {
          NumberAnimation {
            id: fadeAnim
            duration: 80
            easing.type: Easing.OutQuad
          }
        }

        Behavior on scale {
          NumberAnimation {
            duration: 80
            easing.type: Easing.OutQuad
          }
        }

        // Swallow clicks so they don't fall through to the dismiss-area
        // MouseArea behind the panel.
        MouseArea {
          anchors.fill: parent
          onClicked: {}
        }

        Column {
          anchors.fill: parent
          anchors.margins: 16
          spacing: 10

          Item {
            id: headerRow
            width: parent.width
            height: 24

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: Menus.MenuState.promptText.toUpperCase()
              color: Wallust.textMuted
              font.family: "Comic Code"
              font.pixelSize: 10
              font.bold: true
            }

            Rectangle {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(24, countLabel.implicitWidth + 10)
              height: 20
              color: "transparent"
              border.width: 1
              border.color: root.borderSubtle

              Text {
                id: countLabel
                anchors.centerIn: parent
                text: menuList.count
                color: Wallust.textMuted
                font.family: "Comic Code"
                font.pixelSize: 10
                font.bold: true
              }
            }
          }

          Rectangle {
            id: filterBox
            width: parent.width
            height: 34
            color: root.cardSurface
            border.width: 1
            border.color: filterInput.activeFocus ? Wallust.accentPrimary : root.borderSubtle

            TextInput {
              id: filterInput
              anchors.fill: parent
              anchors.margins: 8
              color: Wallust.text
              font.family: "Comic Code"
              font.pixelSize: 11
              verticalAlignment: Text.AlignVCenter
              clip: true
              selectByMouse: true
              selectedTextColor: Wallust.bg
              selectionColor: Wallust.accentPrimary
              onTextChanged: Menus.MenuState.setFilterText(text)
            }

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: 8
              visible: filterInput.text === "" && !filterInput.activeFocus
              text: "TYPE TO FILTER"
              color: Wallust.textDim
              font.family: "Comic Code"
              font.pixelSize: 11
            }
          }

          Item {
            width: parent.width
            height: parent.height - y

            ListView {
              id: menuList
              anchors.fill: parent
              clip: true
              spacing: 4
              model: Menus.MenuState.filteredItems
              currentIndex: count > 0 ? 0 : -1
              visible: count > 0

              delegate: Menus.MenuItem {
                id: menuItem
                required property var modelData

                width: menuList.width
                text: String(modelData.text || "")
                sub: String(modelData.sub || "")
                selected: ListView.isCurrentItem
                onActivated: Menus.MenuState.activateCurrent(menuItem.index)
              }
            }

            Column {
              id: emptyState
              anchors.centerIn: parent
              spacing: 4
              visible: !menuList.visible

              Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "∅"
                color: Wallust.textDim
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: 13 * 2
              }

              Text {
                text: "NO MATCHES"
                color: Wallust.textDim
                font.family: "Comic Code"
                font.pixelSize: 10
                font.bold: true
              }
            }
          }
        }
      }

      Timer {
        id: focusTimer
        interval: 50
        repeat: false
        onTriggered: filterInput.forceActiveFocus()
      }

      onOverlayVisibleChanged: {
        if (overlayVisible) focusTimer.restart()
      }

      function ensureValidSelection() {
        if (menuList.count === 0) {
          menuList.currentIndex = -1
          return
        }

        if (menuList.currentIndex < 0 || menuList.currentIndex >= menuList.count) {
          menuList.currentIndex = 0
        }
      }

      function moveSelection(delta) {
        ensureValidSelection()
        if (menuList.count === 0) return

        const nextIndex = Math.max(0, Math.min(menuList.count - 1, menuList.currentIndex + delta))
        menuList.currentIndex = nextIndex
        menuList.positionViewAtIndex(nextIndex, ListView.Contain)
      }

      Connections {
        target: Menus.MenuState.filteredItems

        function onCountChanged() {
          menuWindow.ensureValidSelection()
        }
      }
    }
  }

  IpcHandler {
    target: "menu"

    function openApps(monitorName: string): void { Menus.MenuState.showApps(monitorName) }
    function openFavorites(monitorName: string): void { Menus.MenuState.showFavorites(monitorName) }
    function openTools(monitorName: string): void { Menus.MenuState.showTools(monitorName) }
    function openPower(monitorName: string): void { Menus.MenuState.showPower(monitorName) }
    function openWindows(monitorName: string): void { Menus.MenuState.showWindows(monitorName) }

    function openDmenu(monitorName: string, prompt: string, itemsText: string, noCustom: bool, selectedRow: int, resultFifo: string): void {
      Menus.MenuState.showDmenu(monitorName, prompt, itemsText, noCustom, selectedRow, resultFifo)
    }

    function hide(): void { Menus.MenuState.hide() }
  }
}
