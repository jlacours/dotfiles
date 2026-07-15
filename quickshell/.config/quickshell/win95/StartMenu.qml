import Quickshell
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

PopupWindow {
  id: root

  required property var barWindow
  required property var startButton
  property string submenu: ""

  readonly property int mainWidth: 224
  readonly property int mainHeight: 240
  readonly property int submenuWidth: 276
  readonly property int programsHeight: Math.min(560, barWindow.screen.height - 64)
  readonly property int settingsHeight: 104
  readonly property var applications: DesktopEntries.applications.values
    .slice()
    .sort((a, b) => a.name.localeCompare(b.name))

  function toggle(): void {
    if (visible) {
      close();
      return;
    }

    visible = true;
  }

  function close(): void {
    visible = false;
  }

  function openPrograms(): void {
    submenu = "programs";
    visible = true;
  }

  function showSubmenu(name: string): void {
    submenu = submenu === name ? "" : name;
  }

  function run(command): void {
    close();
    Quickshell.execDetached(command);
  }

  anchor.window: barWindow
  anchor.rect.x: startButton
    ? startButton.mapToItem(barWindow.contentItem, 0, 0).x
    : 0
  anchor.rect.y: startButton
    ? startButton.mapToItem(barWindow.contentItem, 0, 0).y
    : 0
  anchor.rect.width: startButton ? startButton.width : 1
  anchor.rect.height: startButton ? startButton.height : 1
  anchor.edges: Edges.Top | Edges.Left
  anchor.gravity: Edges.Top | Edges.Right

  color: "transparent"
  // Quickshell maps this to a native Qt::Popup. Labwc then dismisses the menu
  // on an outside click and Quickshell updates visible=false for us. This is a
  // real popup grab, not a fullscreen transparent click catcher.
  grabFocus: true
  implicitWidth: mainWidth + (submenu === "" ? 0 : submenuWidth - 2)
  implicitHeight: submenu === "programs" ? programsHeight : mainHeight

  onVisibleChanged: {
    if (!visible) {
      submenu = "";
    }
  }

  // Safety exits for compositor regressions: Escape is immediate, and a stale
  // native grab can never trap keyboard focus indefinitely.
  Shortcut {
    sequence: "Escape"
    enabled: root.visible
    onActivated: root.close()
  }

  Timer {
    interval: 15000
    running: root.visible
    onTriggered: root.close()
  }

  component MenuEntry: Rectangle {
    required property string label
    property string icon: ""
    property bool hasSubmenu: false
    property bool selected: false
    signal activated()

    width: root.mainWidth - 31
    height: 38
    color: entryMouse.containsMouse || selected
      ? Win95Theme.highlight
      : "transparent"

    IconImage {
      anchors {
        left: parent.left
        leftMargin: 7
        verticalCenter: parent.verticalCenter
      }
      implicitSize: 24
      source: parent.icon
      visible: source !== ""
    }

    Text {
      anchors {
        left: parent.left
        leftMargin: 39
        right: arrow.left
        rightMargin: 4
        verticalCenter: parent.verticalCenter
      }
      text: parent.label
      color: entryMouse.containsMouse || parent.selected
        ? Win95Theme.highlightText
        : Win95Theme.text
      font.family: "Comic Code"
      font.pixelSize: 13
      renderType: Text.NativeRendering
      elide: Text.ElideRight
    }

    Text {
      id: arrow
      anchors {
        right: parent.right
        rightMargin: 7
        verticalCenter: parent.verticalCenter
      }
      text: parent.hasSubmenu ? "▸" : ""
      color: entryMouse.containsMouse || parent.selected
        ? Win95Theme.highlightText
        : Win95Theme.text
      font.family: "Comic Code"
      font.pixelSize: 13
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: entryMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: parent.activated()
    }
  }

  component SubmenuEntry: Rectangle {
    required property string label
    property string icon: ""
    signal activated()

    width: root.submenuWidth - 6
    height: 32
    color: submenuMouse.containsMouse ? Win95Theme.highlight : "transparent"

    IconImage {
      anchors {
        left: parent.left
        leftMargin: 5
        verticalCenter: parent.verticalCenter
      }
      implicitSize: 20
      source: parent.icon
      visible: source !== ""
    }

    Text {
      anchors {
        left: parent.left
        leftMargin: 33
        right: parent.right
        rightMargin: 6
        verticalCenter: parent.verticalCenter
      }
      text: parent.label
      color: submenuMouse.containsMouse
        ? Win95Theme.highlightText
        : Win95Theme.text
      font.family: "Comic Code"
      font.pixelSize: 12
      renderType: Text.NativeRendering
      elide: Text.ElideRight
    }

    MouseArea {
      id: submenuMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: parent.activated()
    }
  }

  BevelRect {
    id: mainPanel
    anchors {
      left: parent.left
      bottom: parent.bottom
    }
    width: root.mainWidth
    height: root.mainHeight

    Rectangle {
      id: banner
      anchors {
        top: parent.top
        bottom: parent.bottom
        left: parent.left
        margins: 3
        rightMargin: 0
      }
      width: 25
      color: Win95Theme.highlight

      Text {
        anchors.centerIn: parent
        text: "juju95"
        color: Win95Theme.highlightText
        font.family: "Comic Code"
        font.pixelSize: 18
        font.bold: true
        renderType: Text.NativeRendering
        rotation: -90
      }
    }

    Column {
      anchors {
        top: parent.top
        left: banner.right
        right: parent.right
        margins: 3
        leftMargin: 0
      }
      spacing: 0

      MenuEntry {
        label: "Programs"
        icon: Quickshell.iconPath("applications-other", true)
        hasSubmenu: true
        selected: root.submenu === "programs"
        onActivated: root.showSubmenu("programs")
      }

      MenuEntry {
        label: "Settings"
        icon: Quickshell.iconPath("preferences-system", true)
        hasSubmenu: true
        selected: root.submenu === "settings"
        onActivated: root.showSubmenu("settings")
      }

      MenuEntry {
        label: "Find"
        icon: Quickshell.iconPath("system-search", true)
        onActivated: {
          root.close();
          Win95MenuState.showApps("");
        }
      }

      Item {
        width: parent.width
        height: 66
      }

      Item {
        width: parent.width
        height: 16

        Rectangle {
          anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
          }
          height: 1
          color: Win95Theme.edgeShadow
        }
        Rectangle {
          anchors {
            left: parent.left
            right: parent.right
            top: parent.verticalCenter
          }
          height: 1
          color: Win95Theme.edgeLight
        }
      }

      MenuEntry {
        label: "Shut Down…"
        icon: Quickshell.iconPath("system-shutdown", true)
        onActivated: {
          root.close();
          Win95MenuState.showPower("");
        }
      }
    }
  }

  BevelRect {
    visible: root.submenu === "programs"
    anchors {
      left: mainPanel.right
      leftMargin: -2
      top: parent.top
      topMargin: 3
    }
    width: root.submenuWidth
    height: root.programsHeight

    ListView {
      id: programsList
      anchors {
        fill: parent
        margins: 3
      }
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.applications

      delegate: Rectangle {
        required property var modelData
        width: programsList.width
        height: 32
        color: appMouse.containsMouse ? Win95Theme.highlight : "transparent"

        readonly property string iconSource: {
          let path = Quickshell.iconPath(modelData.icon, true);
          if (!path)
            path = Quickshell.iconPath("application-x-executable", true);
          return path;
        }

        IconImage {
          anchors {
            left: parent.left
            leftMargin: 5
            verticalCenter: parent.verticalCenter
          }
          implicitSize: 20
          source: parent.iconSource
        }

        Text {
          anchors {
            left: parent.left
            leftMargin: 33
            right: parent.right
            rightMargin: 6
            verticalCenter: parent.verticalCenter
          }
          text: parent.modelData.name
          color: appMouse.containsMouse
            ? Win95Theme.highlightText
            : Win95Theme.text
          font.family: "Comic Code"
          font.pixelSize: 12
          renderType: Text.NativeRendering
          elide: Text.ElideRight
        }

        MouseArea {
          id: appMouse
          anchors.fill: parent
          hoverEnabled: true
          onClicked: {
            root.close();
            parent.modelData.execute();
          }
        }
      }

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
      }
    }
  }

  BevelRect {
    visible: root.submenu === "settings"
    anchors {
      left: mainPanel.right
      leftMargin: -2
      top: parent.top
      topMargin: 41
    }
    width: root.submenuWidth
    height: root.settingsHeight

    Column {
      anchors {
        fill: parent
        margins: 3
      }

      SubmenuEntry {
        label: "Light theme"
        icon: Quickshell.iconPath("weather-clear", true)
        onActivated: root.run([
          Quickshell.env("HOME") + "/.config/labwc/scripts/win95-mode.sh",
          "light"
        ])
      }
      SubmenuEntry {
        label: "Dark theme"
        icon: Quickshell.iconPath("weather-clear-night", true)
        onActivated: root.run([
          Quickshell.env("HOME") + "/.config/labwc/scripts/win95-mode.sh",
          "dark"
        ])
      }
      SubmenuEntry {
        label: "Restart taskbar"
        icon: Quickshell.iconPath("view-refresh", true)
        onActivated: root.run([
          Quickshell.env("HOME") + "/.config/quickshell/scripts/qs-switch.sh",
          "restart"
        ])
      }
    }
  }
}
