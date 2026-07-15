import QtQuick
import Quickshell
import Quickshell.Widgets

// One taskbar button per toplevel window. Sunken while the window is active;
// click toggles activate/minimize, Win95-style.
BevelRect {
  id: button
  required property var modelData

  pressed: modelData.activated

  Rectangle {
    anchors { fill: parent; margins: 2 }
    visible: button.pressed && Win95Theme.dark
    color: Win95Theme.pressedFace
  }

  // Win95 marks the active task with a white/silver checker dither.
  Image {
    anchors { fill: parent; margins: 2 }
    visible: button.pressed && !Win95Theme.dark
    source: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAFElEQVR4nGP4////gQMHGIAYyAIASWQKe3ueQDwAAAAASUVORK5CYII="
    fillMode: Image.Tile
    smooth: false
  }

  function normalized(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/\.desktop$/, "")
      .replace(/[^a-z0-9]+/g, "");
  }

  // Wayland app IDs frequently differ from icon names. Match the toplevel to
  // its desktop entry through id or StartupWMClass before trying icon-theme
  // guesses. This also preserves absolute icons used by AppImage launchers.
  readonly property var desktopEntry: {
    const appId = String(modelData.appId || "");
    const wanted = normalized(appId);
    const wantedTitle = normalized(modelData.title);
    const direct = DesktopEntries.byId(appId)
      || DesktopEntries.byId(appId + ".desktop");
    if (direct)
      return direct;

    const entries = DesktopEntries.applications.values;
    for (let i = 0; i < entries.length; ++i) {
      const entry = entries[i];
      if (normalized(entry.id) === wanted
          || normalized(entry.startupClass) === wanted
          || normalized(entry.name) === wantedTitle)
        return entry;
    }
    return null;
  }

  function iconPath(icon) {
    const value = String(icon || "");
    if (value.startsWith("/"))
      return "file://" + value;
    return value ? Quickshell.iconPath(value, true) : "";
  }

  readonly property string iconSource: {
    if (desktopEntry && desktopEntry.icon) {
      const entryIcon = iconPath(desktopEntry.icon);
      if (entryIcon)
        return entryIcon;
    }

    const appId = String(modelData.appId || "");
    const shortId = appId.includes(".") ? appId.split(".").pop() : appId;
    return iconPath(appId)
      || iconPath(appId.toLowerCase())
      || iconPath(shortId.toLowerCase())
      || iconPath("application-x-executable");
  }

  Row {
    anchors {
      left: parent.left
      leftMargin: button.pressed ? 7 : 6
      right: parent.right
      rightMargin: 4
      verticalCenter: parent.verticalCenter
      verticalCenterOffset: button.pressed ? 1 : 0
    }
    spacing: 5

    IconImage {
      anchors.verticalCenter: parent.verticalCenter
      implicitSize: 16
      source: button.iconSource
      visible: button.iconSource !== ""
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - (button.iconSource !== "" ? 21 : 0)
      text: button.modelData.title || button.modelData.appId || "?"
      color: Win95Theme.text
      font.family: "Comic Code"
      font.pixelSize: 11
      font.bold: button.modelData.activated
      elide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: {
      if (button.modelData.activated)
        button.modelData.minimized = true;
      else
        button.modelData.activate();
    }
  }
}
