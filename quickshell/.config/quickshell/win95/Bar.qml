import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick
import QtQuick.Layouts

// Win95 taskbar: themed chrome, bottom of every screen. Start button, task
// buttons, sunken tray well with clock.
Scope {
  id: scope
  property var activeMenu: null
  property var menusByOutput: ({})

  function currentStartMenu() {
    const active = ToplevelManager.activeToplevel;
    if (active && active.screens && active.screens.length > 0) {
      const candidate = menusByOutput[active.screens[0].name];
      if (candidate)
        return candidate;
    }
    const screens = Quickshell.screens;
    if (screens.length > 0 && menusByOutput[screens[0].name])
      return menusByOutput[screens[0].name];
    return activeMenu;
  }

  IpcHandler {
    target: "startmenu"

    function toggle(): void {
      const menu = scope.currentStartMenu();
      if (menu)
        menu.toggle();
    }

    function openPrograms(): void {
      Win95MenuState.cancelCurrent();
      const menu = scope.currentStartMenu();
      if (menu)
        menu.openPrograms();
    }

    function hide(): void {
      if (scope.activeMenu)
        scope.activeMenu.close();
    }
  }

  IpcHandler {
    target: "menu"

    function openApps(monitorName: string): void { Win95MenuState.showApps(monitorName); }
    function openFavorites(monitorName: string): void { Win95MenuState.showFavorites(monitorName); }
    function openTools(monitorName: string): void { Win95MenuState.showTools(monitorName); }
    function openPower(monitorName: string): void { Win95MenuState.showPower(monitorName); }
    function openWindows(monitorName: string): void { Win95MenuState.showWindows(monitorName); }
    function openDmenuFile(monitorName: string, prompt: string, itemsPath: string,
        noCustom: bool, selectedRow: int, resultFifo: string): void {
      Win95MenuState.showDmenuFile(
        monitorName, prompt, itemsPath, noCustom, selectedRow, resultFifo
      );
    }
    function hide(): void { Win95MenuState.cancelCurrent(); }
  }

  IpcHandler {
    target: "output"

    // Labwc has no CLI to query the focused monitor; scripts (for example
    // the screenshot helper) ask the shell instead.
    function focused(): string { return Win95MenuState.defaultScreenName(); }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: barWindow
      required property var modelData

      readonly property int barHeight: 32

      screen: modelData
      color: Win95Theme.face

      anchors {
        bottom: true
        left: true
        right: true
      }

      implicitHeight: barHeight
      exclusiveZone: barHeight

      Component.onCompleted: {
        const registered = Object.assign({}, scope.menusByOutput);
        registered[modelData.name] = startMenu;
        scope.menusByOutput = registered;
        if (!scope.activeMenu)
          scope.activeMenu = startMenu;
      }

      SystemClock {
        id: clock
        precision: SystemClock.Minutes
      }

      // Raised top edge of the taskbar itself.
      Rectangle {
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 1
        color: Win95Theme.edgeLight
      }

      RowLayout {
        anchors {
          fill: parent
          topMargin: 3
          bottomMargin: 2
          leftMargin: 2
          rightMargin: 2
        }
        spacing: 4

        BevelRect {
          id: startButton
          Layout.preferredWidth: startRow.implicitWidth + 16
          Layout.fillHeight: true
          pressed: startMenu.open || startMouse.pressed

          Row {
            id: startRow
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: startButton.pressed ? 1 : 0
            anchors.verticalCenterOffset: startButton.pressed ? 1 : 0
            spacing: 5

            // The genuine waving flag, courtesy of the user.
            Image {
              anchors.verticalCenter: parent.verticalCenter
              source: Qt.resolvedUrl("start-flag.svg")
              sourceSize: Qt.size(18, 18)
              width: 18
              height: 18
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Start"
              color: Win95Theme.text
              font.family: "Comic Code"
              font.pixelSize: 12
              font.bold: true
            }
          }

          MouseArea {
            id: startMouse
            anchors.fill: parent
            onClicked: {
              Win95MenuState.cancelCurrent();
              if (scope.activeMenu && scope.activeMenu !== startMenu)
                scope.activeMenu.close();
              scope.activeMenu = startMenu;
              startMenu.toggle();
            }
          }
        }

        // Task buttons compress as they multiply, exactly like the original.
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 3

          Repeater {
            model: ToplevelManager.toplevels.values

            TaskButton {
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.maximumWidth: 180
              Layout.minimumWidth: 48
            }
          }

          // Eats leftover width so few windows means small buttons on the left.
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            MouseArea {
              anchors.fill: parent
              onClicked: Win95MenuState.requestStartClose()
            }
          }
        }

        // Sunken tray well: SNI icons + clock. Thin 1px bevel like the real one.
        BevelRect {
          thin: true
          Layout.preferredWidth: trayRow.implicitWidth + 18
          Layout.fillHeight: true

          Row {
            id: trayRow
            anchors.centerIn: parent
            spacing: 6

            Repeater {
              model: SystemTray.items

              IconImage {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: 16
                source: modelData.icon

                MouseArea {
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  onClicked: (mouse) => {
                    Win95MenuState.requestStartClose();
                    if (mouse.button === Qt.RightButton && modelData.hasMenu)
                      menuAnchor.open();
                    else
                      modelData.activate();
                  }
                }

                QsMenuAnchor {
                  id: menuAnchor
                  menu: modelData.menu
                  anchor.window: barWindow
                }
              }
            }

            KeepAwakeButton {
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: Qt.formatTime(clock.date, "h:mm AP")
              color: Win95Theme.text
              font.family: "Comic Code"
              font.pixelSize: 12

              MouseArea {
                anchors.fill: parent
                onClicked: Win95MenuState.requestStartClose()
              }
            }
          }
        }
      }

      StartMenu {
        id: startMenu
        barWindow: barWindow
        coordinator: scope
      }

      Win95Menu {
        barWindow: barWindow
        outputName: modelData.name
      }

      Connections {
        target: Win95MenuState
        function onVisibleChanged(): void {
          if (Win95MenuState.visible)
            startMenu.close();
        }
        function onCloseStartRequested(): void { startMenu.close(); }
      }
    }
  }
}
