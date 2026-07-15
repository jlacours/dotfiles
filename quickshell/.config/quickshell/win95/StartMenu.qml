import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

FloatingWindow {
  id: root

  required property var barWindow
  required property var startButton
  required property var coordinator
  property bool open: false
  property bool wasActive: false
  property string submenu: ""
  property string programSearch: ""
  property int selectedProgramIndex: applications.length > 0 ? 0 : -1

  readonly property bool isOwner: coordinator.activeMenu === root

  readonly property int mainWidth: 224
  readonly property int mainHeight: 250
  readonly property int submenuWidth: 276
  readonly property int programsHeight: Math.min(560, barWindow.screen.height - 64)
  readonly property int settingsHeight: 104
  readonly property var applications: DesktopEntries.applications.values
    .slice()
    .sort((a, b) => a.name.localeCompare(b.name))

  function toggle(): void {
    if (open) {
      close();
      return;
    }

    if (coordinator.activeMenu && coordinator.activeMenu !== root)
      coordinator.activeMenu.close();
    coordinator.activeMenu = root;
    open = true;
  }

  function close(): void {
    open = false;
  }

  function openPrograms(): void {
    if (coordinator.activeMenu && coordinator.activeMenu !== root)
      coordinator.activeMenu.close();
    coordinator.activeMenu = root;
    submenu = "programs";
    programSearch = "";
    selectedProgramIndex = applications.length > 0 ? 0 : -1;
    open = true;
  }

  function showSubmenu(name: string): void {
    submenu = submenu === name ? "" : name;
    if (submenu === "programs") {
      programSearch = "";
      selectedProgramIndex = programsList.count > 0 ? 0 : -1;
    }
  }

  function run(command): void {
    close();
    Quickshell.execDetached(command);
  }

  function launchProgram(index): void {
    if (index < 0 || index >= applications.length)
      return;
    const application = applications[index];
    close();
    application.execute();
  }

  function findProgram(query, startIndex): int {
    if (applications.length === 0)
      return -1;
    for (let offset = 0; offset < applications.length; offset++) {
      const index = (startIndex + offset) % applications.length;
      if (applications[index].name.toLowerCase().startsWith(query))
        return index;
    }
    return -1;
  }

  function handleProgramText(text): void {
    if (submenu !== "programs")
      return;

    const typed = text.toLowerCase();
    if (!/^[a-z]$/.test(typed))
      return;

    let query = typed;
    let startIndex = selectedProgramIndex + 1;
    if (programSearchTimer.running && programSearch !== typed) {
      query = programSearch + typed;
      startIndex = 0;
    }

    let match = findProgram(query, startIndex);
    if (match < 0 && query.length > 1) {
      query = typed;
      match = findProgram(query, selectedProgramIndex + 1);
    }

    programSearch = query;
    programSearchTimer.restart();
    if (match >= 0) {
      selectedProgramIndex = match;
      programsList.positionViewAtIndex(match, ListView.Contain);
    }
  }

  screen: barWindow.screen
  title: "juju95-start-menu-" + barWindow.screen.name
  color: "transparent"
  visible: open
  implicitWidth: mainWidth + submenuWidth - 2
  implicitHeight: programsHeight
  minimumSize: Qt.size(implicitWidth, implicitHeight)
  maximumSize: minimumSize

  onOpenChanged: {
    if (open) {
      wasActive = false;
    } else {
      submenu = "";
      programSearch = "";
    }
  }

  Connections {
    target: ToplevelManager

    function onActiveToplevelChanged(): void {
      const active = ToplevelManager.activeToplevel;
      if (active && active.title === root.title) {
        root.wasActive = true;
      } else if (root.open && root.wasActive) {
        root.close();
      }
    }
  }

  // Safety exits for compositor regressions: Escape is immediate, and a stale
  // native grab can never trap keyboard focus indefinitely.
  Shortcut {
    sequence: "Escape"
    enabled: root.open && root.isOwner
    onActivated: root.close()
  }

  Shortcut {
    sequence: "Return"
    enabled: root.open && root.isOwner
      && root.submenu === "programs"
      && root.selectedProgramIndex >= 0
    onActivated: root.launchProgram(root.selectedProgramIndex)
  }

  Shortcut {
    sequence: "Down"
    enabled: root.open && root.isOwner
      && root.submenu === "programs"
      && programsList.count > 0
    onActivated: {
      root.selectedProgramIndex = Math.min(
        programsList.count - 1,
        root.selectedProgramIndex + 1
      );
      programsList.positionViewAtIndex(
        root.selectedProgramIndex,
        ListView.Contain
      );
    }
  }

  Shortcut {
    sequence: "Up"
    enabled: root.open && root.isOwner
      && root.submenu === "programs"
      && programsList.count > 0
    onActivated: {
      root.selectedProgramIndex = Math.max(0, root.selectedProgramIndex - 1);
      programsList.positionViewAtIndex(
        root.selectedProgramIndex,
        ListView.Contain
      );
    }
  }

  component ProgramKey: Shortcut {
    required property string letter
    sequence: letter.toUpperCase()
    enabled: root.open && root.isOwner && root.submenu === "programs"
    onActivated: root.handleProgramText(letter)
  }

  ProgramKey { letter: "a" }
  ProgramKey { letter: "b" }
  ProgramKey { letter: "c" }
  ProgramKey { letter: "d" }
  ProgramKey { letter: "e" }
  ProgramKey { letter: "f" }
  ProgramKey { letter: "g" }
  ProgramKey { letter: "h" }
  ProgramKey { letter: "i" }
  ProgramKey { letter: "j" }
  ProgramKey { letter: "k" }
  ProgramKey { letter: "l" }
  ProgramKey { letter: "m" }
  ProgramKey { letter: "n" }
  ProgramKey { letter: "o" }
  ProgramKey { letter: "p" }
  ProgramKey { letter: "q" }
  ProgramKey { letter: "r" }
  ProgramKey { letter: "s" }
  ProgramKey { letter: "t" }
  ProgramKey { letter: "u" }
  ProgramKey { letter: "v" }
  ProgramKey { letter: "w" }
  ProgramKey { letter: "x" }
  ProgramKey { letter: "y" }
  ProgramKey { letter: "z" }

  Timer {
    id: programSearchTimer
    interval: 900
    onTriggered: root.programSearch = ""
  }

  Timer {
    interval: 15000
    running: root.open && root.isOwner
    onTriggered: root.close()
  }

  // Focus changes and the existing desktop/taskbar surfaces close the normal
  // window. This handles its own transparent Win95 silhouette.
  MouseArea {
    anchors.fill: parent
    onClicked: {
      if (root.coordinator.activeMenu)
        root.coordinator.activeMenu.close();
    }
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
    visible: root.isOwner
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

      MenuEntry {
        label: "Favorites"
        icon: Quickshell.iconPath("emblem-favorite", true)
        onActivated: {
          root.close();
          Win95MenuState.showFavorites("");
        }
      }

      MenuEntry {
        label: "Tools"
        icon: Quickshell.iconPath("applications-utilities", true)
        onActivated: {
          root.close();
          Win95MenuState.showTools("");
        }
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
    visible: root.isOwner && root.submenu === "programs"
    anchors {
      left: mainPanel.right
      leftMargin: -2
      bottom: parent.bottom
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
      currentIndex: root.selectedProgramIndex

      delegate: Rectangle {
        id: appRow
        required property var modelData
        required property int index
        width: programsList.width
        height: 32
        color: appMouse.containsMouse || ListView.isCurrentItem
          ? Win95Theme.highlight
          : "transparent"

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
          color: appMouse.containsMouse || appRow.ListView.isCurrentItem
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
            root.launchProgram(appRow.index);
          }
        }
      }

      ScrollBar.vertical: ScrollBar {
        policy: ScrollBar.AsNeeded
      }
    }
  }

  BevelRect {
    id: settingsPanel
    visible: root.isOwner && root.submenu === "settings"
    anchors {
      left: mainPanel.right
      leftMargin: -2
      top: mainPanel.top
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
