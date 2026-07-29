pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Persistent state and file discovery for the Win95 Display Properties dialog.
Singleton {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || home + "/.local/state"
  readonly property string wallpaperDir: home + "/Pictures/Wallpapers"
  readonly property string wallpaperStatePath: stateHome
    + "/quickshell/win95-wallpaper"
  readonly property string placementStatePath: stateHome
    + "/quickshell/win95-wallpaper-placement"
  readonly property alias wallpapers: wallpaperModel

  property bool visible: false
  property string screenName: ""
  property string wallpaperPath: ""
  property string placement: "fill"
  property string selectedPath: ""
  property string selectedPlacement: "fill"
  property int selectedIndex: 0
  property int listSerial: 0

  function defaultScreenName(): string {
    const active = ToplevelManager.activeToplevel;
    if (active && active.screens && active.screens.length > 0)
      return active.screens[0].name;
    return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
  }

  function open(monitorName): void {
    screenName = monitorName || defaultScreenName();
    selectedPath = wallpaperPath;
    selectedPlacement = placement;
    visible = true;
    refreshWallpapers();
  }

  function cancel(): void {
    selectedPath = wallpaperPath;
    selectedPlacement = placement;
    syncSelection();
    visible = false;
  }

  function applySelection(): void {
    wallpaperPath = selectedPath;
    placement = selectedPlacement;

    if (selectedPath === "") {
      applyProcess.exec([
        home + "/.config/quickshell/scripts/wallpaper-apply.sh",
        "--clear",
        placement
      ]);
    } else {
      applyProcess.exec([
        home + "/.config/quickshell/scripts/wallpaper-apply.sh",
        selectedPath,
        placement
      ]);
    }
  }

  function accept(): void {
    applySelection();
    visible = false;
  }

  function select(index): void {
    if (index < 0 || index >= wallpaperModel.count)
      return;
    selectedIndex = index;
    selectedPath = wallpaperModel.get(index).path;
  }

  function moveSelection(delta): void {
    if (wallpaperModel.count === 0)
      return;
    select(Math.max(0, Math.min(
      wallpaperModel.count - 1,
      selectedIndex + delta
    )));
  }

  function syncSelection(): void {
    selectedIndex = 0;
    for (let i = 0; i < wallpaperModel.count; i++) {
      if (wallpaperModel.get(i).path === selectedPath) {
        selectedIndex = i;
        return;
      }
    }
  }

  function refreshWallpapers(): void {
    wallpaperListProcess.exec([
      "find", wallpaperDir,
      "-maxdepth", "1",
      "-type", "f",
      "(",
      "-iname", "*.png", "-o",
      "-iname", "*.jpg", "-o",
      "-iname", "*.jpeg", "-o",
      "-iname", "*.webp", "-o",
      "-iname", "*.jxl",
      ")",
      "-printf", "%f\t%p\n"
    ]);
  }

  function populateWallpapers(text): void {
    const entries = [];
    for (const line of text.split("\n")) {
      const separator = line.indexOf("\t");
      if (separator <= 0)
        continue;
      entries.push({
        name: line.slice(0, separator),
        path: line.slice(separator + 1)
      });
    }
    entries.sort((a, b) => a.name.localeCompare(b.name));

    wallpaperModel.clear();
    wallpaperModel.append({ name: "(None)", path: "" });
    for (const entry of entries)
      wallpaperModel.append(entry);

    selectedPath = wallpaperPath;
    syncSelection();
    listSerial += 1;
  }

  function setWallpaper(path, requestedPlacement): void {
    wallpaperPath = path || "";
    placement = requestedPlacement || "fill";
    if (!visible) {
      selectedPath = wallpaperPath;
      selectedPlacement = placement;
      syncSelection();
    }
  }

  ListModel { id: wallpaperModel }

  FileView {
    id: wallpaperFile
    path: root.wallpaperStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.setWallpaper(text().trim(), root.placement)
    onFileChanged: {
      reload();
      root.setWallpaper(text().trim(), root.placement);
    }
  }

  FileView {
    id: placementFile
    path: root.placementStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.setWallpaper(root.wallpaperPath, text().trim())
    onFileChanged: {
      reload();
      root.setWallpaper(root.wallpaperPath, text().trim());
    }
  }

  Process {
    id: wallpaperListProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.populateWallpapers(text)
    }
  }

  Process { id: applyProcess }
  Process { id: openFolderProcess }

  function openFolder(): void {
    openFolderProcess.exec(["pcmanfm", wallpaperDir]);
  }

  IpcHandler {
    target: "wallpaper"

    function open(monitorName: string): void {
      Win95MenuState.cancelCurrent();
      root.open(monitorName);
    }

    function hide(): void { root.cancel(); }

    function setWallpaper(path: string, requestedPlacement: string): void {
      root.setWallpaper(path, requestedPlacement);
    }
  }
}
