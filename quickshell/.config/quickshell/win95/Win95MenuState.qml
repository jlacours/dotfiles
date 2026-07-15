pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Labwc-native launcher state. This deliberately mirrors the useful shape of
// the square profile's menu without importing its Hyprland IPC or presentation.
Singleton {
  id: root

  signal closeStartRequested

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string scriptsDir: home + "/.config/quickshell/scripts"

  property bool visible: false
  property string screenName: ""
  property string mode: ""
  property string promptText: ""
  property string filterText: ""
  property bool noCustom: false
  property int initialSelectedRow: 0
  property int resetSelectionSerial: 0
  property string resultFifo: ""

  readonly property alias filteredItems: filteredModel

  function defaultScreenName(): string {
    const active = ToplevelManager.activeToplevel;
    if (active && active.screens && active.screens.length > 0)
      return active.screens[0].name;
    return Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "";
  }

  function clearItems(): void {
    itemsModel.clear();
    filteredModel.clear();
  }

  function addItem(text, sub, kind, payload): void {
    itemsModel.append({
      text: text,
      sub: sub || "",
      kind: kind,
      payload: payload === undefined ? "" : payload
    });
  }

  function refreshFiltered(): void {
    filteredModel.clear();
    const needle = filterText.toLowerCase();

    for (let i = 0; i < itemsModel.count; i++) {
      const item = itemsModel.get(i);
      if (needle
          && item.text.toLowerCase().indexOf(needle) < 0
          && item.sub.toLowerCase().indexOf(needle) < 0)
        continue;

      filteredModel.append({
        text: item.text,
        sub: item.sub,
        kind: item.kind,
        payload: item.payload,
        sourceIndex: i
      });
    }
  }

  function setFilterText(text): void {
    filterText = text || "";
    refreshFiltered();
  }

  function begin(modeName, requestedScreen, prompt): bool {
    if (root.mode === "dmenu" && root.resultFifo)
      root.writeResult("");

    const target = requestedScreen || defaultScreenName();
    if (visible && mode === modeName && screenName === target) {
      hide();
      return false;
    }

    mode = modeName;
    screenName = target;
    promptText = prompt;
    filterText = "";
    noCustom = false;
    initialSelectedRow = 0;
    resultFifo = "";
    clearItems();
    visible = true;
    return true;
  }

  function hide(): void {
    visible = false;
    filterText = "";
    resultFifo = "";
  }

  function populateApps(): void {
    clearItems();
    const applications = DesktopEntries.applications.values;
    const sorted = [];
    for (let i = 0; i < applications.length; i++) {
      const entry = applications[i];
      if (!entry || entry.noDisplay)
        continue;
      sorted.push({
        text: entry.name || entry.id,
        sub: entry.genericName || entry.comment || "",
        id: entry.id
      });
    }
    sorted.sort((a, b) => a.text.localeCompare(b.text));
    for (const item of sorted)
      addItem(item.text, item.sub, "app", item.id);
    refreshFiltered();
  }

  function showApps(monitorName): void {
    if (!begin("apps", monitorName, "Applications"))
      return;
    noCustom = true;
    populateApps();
  }

  function showFavorites(monitorName): void {
    if (!begin("favorites", monitorName, "Favorites"))
      return;
    noCustom = true;
    addItem("Applications", "All installed programs", "chain-apps", "");
    addItem("Terminal", "foot", "spawn", JSON.stringify(["foot"]));
    addItem("File manager", "ranger", "spawn", JSON.stringify(["foot", "-e", "ranger"]));
    addItem("Neovim", "terminal editor", "spawn", JSON.stringify(["foot", "--app-id", "nvim", "-e", "nvim"]));
    addItem("Emacs", "graphical client", "spawn", JSON.stringify(["emacsclient", "-c"]));
    addItem("Web browser", "Zen Browser", "spawn", JSON.stringify(["zen-browser", "--new-window"]));
    addItem("Newsboat", "terminal RSS reader", "spawn", JSON.stringify(["foot", "--app-id", "newsboat", "-e", "newsboat"]));
    addItem("Music player", "rmpc", "spawn", JSON.stringify(["foot", "-e", "rmpc"]));
    refreshFiltered();
  }

  function showTools(monitorName): void {
    if (!begin("tools", monitorName, "Tools"))
      return;
    noCustom = true;
    addItem("Screenshot", "save the complete desktop", "spawn",
      JSON.stringify([home + "/.config/labwc/scripts/screenshot.sh", "full"]));
    addItem("Screenshot region", "select and save", "spawn",
      JSON.stringify([home + "/.config/labwc/scripts/screenshot.sh", "region-save"]));
    addItem("Clipboard history", "cliphist", "spawn",
      JSON.stringify(["bash", scriptsDir + "/cliphist.sh"]));
    addItem("Emoji and symbols", "copy a character", "spawn",
      JSON.stringify(["bash", scriptsDir + "/emojis.sh"]));
    addItem("OCR region", "copy text from the screen", "spawn",
      JSON.stringify(["bash", scriptsDir + "/ocr.sh"]));
    addItem("Todo", "manage the task list", "spawn",
      JSON.stringify(["bash", scriptsDir + "/todo.sh"]));
    addItem("Power", "shutdown, reboot, suspend, or log out", "chain-power", "");
    refreshFiltered();
  }

  function showPower(monitorName): void {
    if (!begin("power", monitorName, "Power"))
      return;
    noCustom = true;
    addItem("Shut down", "power off the computer", "spawn", JSON.stringify(["systemctl", "poweroff"]));
    addItem("Restart", "reboot the computer", "spawn", JSON.stringify(["systemctl", "reboot"]));
    addItem("Suspend", "sleep until input resumes it", "spawn", JSON.stringify(["systemctl", "suspend"]));
    addItem("Log out", "exit Labwc", "spawn", JSON.stringify(["labwc", "--exit"]));
    refreshFiltered();
  }

  function showWindows(monitorName): void {
    if (!begin("windows", monitorName, "Windows"))
      return;
    noCustom = true;
    const windows = ToplevelManager.toplevels.values;
    for (let i = 0; i < windows.length; i++) {
      const window = windows[i];
      addItem(window.title || window.appId || "(untitled)", window.appId || "", "window", String(i));
    }
    refreshFiltered();
  }

  function beginDmenu(monitorName, prompt, noCustomArg, selectedRow, fifo): void {
    if (root.mode === "dmenu" && root.resultFifo)
      root.writeResult("");
    screenName = monitorName || defaultScreenName();
    mode = "dmenu";
    promptText = prompt || "Choose";
    noCustom = !!noCustomArg;
    initialSelectedRow = Math.max(0, selectedRow);
    resultFifo = fifo || "";
    filterText = "";
    clearItems();
    visible = true;
  }

  function showDmenuFile(monitorName, prompt, itemsPath, noCustomArg, selectedRow, fifo): void {
    beginDmenu(monitorName, prompt, noCustomArg, selectedRow, fifo);
    dmenuFileProcess.exec(["cat", itemsPath || "/dev/null"]);
  }

  function populateDmenuItems(text): void {
    clearItems();
    const lines = text.length ? text.split("\n") : [];
    if (lines.length && lines[lines.length - 1] === "")
      lines.pop();
    for (let i = 0; i < lines.length; i++)
      addItem(lines[i], "", "dmenu", String(i));
    refreshFiltered();
    resetSelectionSerial += 1;
  }

  function writeResult(text): void {
    if (!resultFifo)
      return;
    fifoWriter.exec([
      "timeout", "5", "/bin/sh", "-c",
      "printf '%s' \"$1\" > \"$2\"", "_", text, resultFifo
    ]);
  }

  function activateCurrent(rowIndex): void {
    if (mode === "dmenu") {
      if (rowIndex >= 0 && rowIndex < filteredModel.count) {
        const item = filteredModel.get(rowIndex);
        writeResult(item.sourceIndex + "\t" + item.text);
      } else if (!noCustom && filterText.length > 0) {
        writeResult("-1\t" + filterText);
      } else {
        return;
      }
      hide();
      return;
    }

    if (rowIndex < 0 || rowIndex >= filteredModel.count)
      return;
    const item = filteredModel.get(rowIndex);

    if (item.kind === "chain-apps") {
      showApps(screenName);
      return;
    }
    if (item.kind === "chain-power") {
      showPower(screenName);
      return;
    }

    const kind = item.kind;
    const payload = item.payload;
    hide();

    if (kind === "app") {
      const entry = DesktopEntries.byId(payload);
      if (entry)
        entry.execute();
    } else if (kind === "spawn") {
      spawnProcess.exec(JSON.parse(payload));
    } else if (kind === "window") {
      const windows = ToplevelManager.toplevels.values;
      const index = Number(payload);
      if (index >= 0 && index < windows.length)
        windows[index].activate();
    }
  }

  function cancelCurrent(): void {
    if (mode === "dmenu")
      writeResult("");
    hide();
  }

  function requestStartClose(): void {
    closeStartRequested();
  }

  ListModel { id: itemsModel }
  ListModel { id: filteredModel }
  Process { id: spawnProcess }
  Process { id: fifoWriter }
  Process {
    id: dmenuFileProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.populateDmenuItems(text)
    }
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged(): void {
      if (root.visible && root.mode === "apps")
        root.populateApps();
    }
  }
}
