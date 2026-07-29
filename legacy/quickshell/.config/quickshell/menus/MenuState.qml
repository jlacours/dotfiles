pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Backing data + logic for the centered menu overlay (CenterMenu.qml).
//
// Replaces rofi: every menu (app launcher, favourites, tools, power, window
// switcher, and the dmenu-compatible shim used by the ported rofi/scripts/*.sh
// scripts) funnels through this single singleton. `mode` selects which
// "show*" populated the list; `activateCurrent`/`cancelCurrent` dispatch by
// mode. See CenterMenu.qml for the IpcHandler entry points and quickshell/
// AGENTS.md for the overall design writeup.
Singleton {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string scriptsDir: home + "/.config/quickshell/scripts"

  property bool visible: false
  property string screenName: ""
  // "apps" | "favorites" | "tools" | "power" | "windows" | "dmenu"
  property string mode: ""
  property string promptText: ""
  property string filterText: ""
  property bool noCustom: false
  property int initialSelectedRow: 0
  property int resetSelectionSerial: 0
  // Only set for mode === "dmenu": the FIFO the CLI shim (qs-dmenu.sh) is
  // blocked reading from. Writing to it (writeResult) is what unblocks it.
  property string resultFifo: ""

  readonly property alias items: itemsModel
  readonly property alias filteredItems: filteredModel

  function clearItems() {
    itemsModel.clear()
    filteredModel.clear()
  }

  function addItem(text, sub, kind, payload) {
    itemsModel.append({ text: text, sub: sub || "", kind: kind, payload: payload || "" })
  }

  function refreshFiltered() {
    filteredModel.clear()
    const needle = filterText.toLowerCase()

    for (let i = 0; i < itemsModel.count; i++) {
      const it = itemsModel.get(i)
      if (needle
          && it.text.toLowerCase().indexOf(needle) < 0
          && it.sub.toLowerCase().indexOf(needle) < 0) continue

      filteredModel.append({
        text: it.text,
        sub: it.sub,
        kind: it.kind,
        payload: it.payload,
        sourceIndex: i
      })
    }
  }

  function requestSelectionReset() {
    resetSelectionSerial += 1
  }

  function setFilterText(text) {
    filterText = text || ""
    refreshFiltered()
  }

  // Returns true if the caller should go on to populate items + show().
  // Returns false if this call just toggled an already-open menu closed
  // (pressing the same bind twice closes the overlay, like the other
  // quickshell overlays).
  function openMenu(newMode, monitorName, prompt) {
    // A Hyprland keybind menu can preempt a dmenu session mid-flight
    // (compositor binds fire despite the overlay's exclusive keyboard
    // focus). Release the blocked qs-dmenu.sh reader (empty write =
    // cancel) before repurposing the overlay, or that script and its
    // parent hang on the FIFO forever.
    if (root.mode === "dmenu" && root.resultFifo) root.writeResult("")

    const targetScreen = monitorName || ""

    if (root.visible && root.mode === newMode && root.screenName === targetScreen) {
      root.hide()
      return false
    }

    root.screenName = targetScreen
    root.mode = newMode
    root.promptText = prompt
    root.filterText = ""
    root.noCustom = false
    root.initialSelectedRow = 0
    root.resultFifo = ""
    root.clearItems()
    root.visible = true
    return true
  }

  function hide() {
    visible = false
    filterText = ""
    // Cleared AFTER any writeResult call in the completion paths (the
    // writer captured the path in its argv), so a later menu open can
    // tell a pending dmenu apart from a completed one.
    resultFifo = ""
  }

  // --- Applications (drun replacement) ---------------------------------
  //
  // Note (verified against quickshell's own source via deepwiki): DesktopEntry
  // .execute() launches the entry's command via Quickshell.execDetached() but
  // explicitly ignores runInTerminal and desktop-file field codes. A handful
  // of Terminal=true .desktop entries (rare) won't get a terminal wrapper the
  // way rofi's drun gave them one. Not worth a bespoke terminal-wrapping path
  // for this port; flagged in the handoff instead.

  function populateApps() {
    root.clearItems()
    const apps = DesktopEntries.applications.values
    const list = []

    for (let i = 0; i < apps.length; i++) {
      const entry = apps[i]
      if (!entry || entry.noDisplay) continue
      list.push({
        text: entry.name || entry.id,
        sub: entry.genericName || entry.comment || "",
        id: entry.id
      })
    }

    list.sort((a, b) => a.text.localeCompare(b.text))
    for (const it of list) root.addItem(it.text, it.sub, "app", it.id)
    root.refreshFiltered()
  }

  function showApps(monitorName) {
    if (!openMenu("apps", monitorName, "Applications")) return

    root.noCustom = true
    root.populateApps()
  }

  // --- Favourites (rofi-apps replacement) -------------------------------
  //
  // Exact list + commands ported from hyprland/.config/hypr/scripts/rofi-apps.sh
  // (verified byte-for-byte via `strings ~/.local/bin/rofi-apps` against the
  // compiled Rust binary bound to Super+B — the two are the same menu).

  function showFavorites(monitorName) {
    if (!openMenu("favorites", monitorName, "Favorites")) return

    root.noCustom = true
    root.addItem("App launcher", "", "chain-apps", "")
    root.addItem("Terminal", "foot", "spawn", JSON.stringify(["foot"]))
    root.addItem("Dropdown terminal", "foot --app-id foot-scratchpad", "spawn",
      JSON.stringify(["foot", "--app-id", "foot-scratchpad", "-o", "colors-dark.alpha=0.9"]))
    root.addItem("Ranger", "foot -e ranger", "spawn",
      JSON.stringify(["foot", "-e", "ranger"]))
    root.addItem("Neovim", "foot -e nvim", "spawn",
      JSON.stringify(["foot", "--app-id", "nvim", "-e", "nvim"]))
    root.addItem("Emacs", "emacsclient -c", "spawn",
      JSON.stringify(["emacsclient", "-c"]))
    root.addItem("Firefox", "firefox --new-window", "spawn",
      JSON.stringify(["firefox", "--new-window"]))
    root.addItem("Brave", "brave --new-window", "spawn",
      JSON.stringify(["brave", "--new-window"]))
    root.addItem("Newsboat", "foot -e newsboat", "spawn",
      JSON.stringify(["foot", "--app-id", "newsboat", "-e", "newsboat"]))
    root.addItem("Music player", "foot -e rmpc", "spawn",
      JSON.stringify(["foot", "-e", "rmpc"]))
    root.refreshFiltered()
  }

  // --- Tools (rofi-tools replacement) -----------------------------------
  //
  // Exact list ported from hyprland/.config/hypr/scripts/rofi-tools.sh
  // (verified byte-for-byte via `strings ~/.local/bin/rofi-tools`).

  function showTools(monitorName) {
    if (!openMenu("tools", monitorName, "Tools")) return

    root.noCustom = true
    const dir = root.scriptsDir
    root.addItem("Screenshot", "", "spawn", JSON.stringify(["bash", dir + "/screenshot.sh"]))
    root.addItem("Screen record", "", "spawn", JSON.stringify(["bash", dir + "/screenrecord.sh"]))
    root.addItem("Clipboard history", "", "spawn", JSON.stringify(["bash", dir + "/cliphist.sh"]))
    root.addItem("Emoji/symbol picker", "", "spawn", JSON.stringify(["bash", dir + "/emojis.sh"]))
    root.addItem("OCR", "", "spawn", JSON.stringify(["bash", dir + "/ocr.sh"]))
    root.addItem("Todo", "", "spawn", JSON.stringify(["bash", dir + "/todo.sh"]))
    root.addItem("Wallpaper picker", "", "spawn", JSON.stringify(["bash", dir + "/wallpaper.sh"]))
    root.addItem("Speak (TTS)", "", "spawn", JSON.stringify(["bash", dir + "/speak.sh"]))
    root.addItem("Power menu", "", "chain-power", "")
    root.refreshFiltered()
  }

  // --- Power menu ---------------------------------------------------------

  function showPower(monitorName) {
    if (!openMenu("power", monitorName, "Power")) return

    root.noCustom = true
    root.addItem("Shutdown", "systemctl poweroff", "power", "Shutdown")
    root.addItem("Reboot", "systemctl reboot", "power", "Reboot")
    root.addItem("Suspend", "systemctl suspend", "power", "Suspend")
    root.addItem("Logout", "hyprctl dispatch exit", "power", "Logout")
    root.refreshFiltered()
  }

  function runPower(action) {
    switch (action) {
      case "Shutdown": powerProcess.exec(["systemctl", "poweroff"]); break
      case "Reboot": powerProcess.exec(["systemctl", "reboot"]); break
      case "Suspend": powerProcess.exec(["systemctl", "suspend"]); break
      case "Logout": Hyprland.dispatch("exit"); break
    }
  }

  // --- Window switcher -----------------------------------------------------

  function showWindows(monitorName) {
    if (!openMenu("windows", monitorName, "Windows")) return

    root.noCustom = true
    if (!clientsProcess.running) clientsProcess.exec(["hyprctl", "clients", "-j"])
  }

  // --- Generic dmenu shim (qs-dmenu.sh) -------------------------------------

  function showDmenu(monitorName, prompt, itemsText, noCustomArg, selectedRow, fifo) {
    root.beginDmenu(monitorName, prompt, noCustomArg, selectedRow, fifo)
    root.populateDmenuItems(itemsText)
  }

  function showDmenuFile(monitorName, prompt, itemsPath, noCustomArg, selectedRow, fifo) {
    root.beginDmenu(monitorName, prompt, noCustomArg, selectedRow, fifo)
    dmenuFileProcess.exec(["cat", itemsPath || "/dev/null"])
  }

  function beginDmenu(monitorName, prompt, noCustomArg, selectedRow, fifo) {
    // Same preemption release as openMenu(): a second dmenu script must
    // not strand the first one's blocked reader.
    if (root.mode === "dmenu" && root.resultFifo) root.writeResult("")

    root.screenName = monitorName || ""
    root.mode = "dmenu"
    root.promptText = prompt || ""
    root.noCustom = !!noCustomArg
    root.initialSelectedRow = Math.max(0, selectedRow)
    root.resultFifo = fifo || ""
    root.filterText = ""
    root.clearItems()
    root.visible = true
  }

  function populateDmenuItems(itemsText) {
    root.clearItems()
    const lines = itemsText.length ? itemsText.split("\n") : []
    if (lines.length > 0 && lines[lines.length - 1] === "") lines.pop()
    for (let i = 0; i < lines.length; i++) root.addItem(lines[i], "", "dmenu", String(i))

    root.refreshFiltered()
    root.requestSelectionReset()
  }

  function writeResult(text) {
    if (!resultFifo) return
    // timeout: if the reader died without cleaning up (e.g. SIGKILLed
    // script), the FIFO open would block forever and wedge fifoWriter.
    fifoWriter.exec(["timeout", "5", "/bin/sh", "-c", "printf '%s' \"$1\" > \"$2\"", "_", text, resultFifo])
  }

  // --- Activation / cancellation -------------------------------------------

  function activateCurrent(rowIndex) {
    if (mode === "dmenu") {
      if (rowIndex >= 0 && rowIndex < filteredModel.count) {
        const it = filteredModel.get(rowIndex)
        writeResult(it.sourceIndex + "\t" + it.text)
      } else if (!noCustom && filterText.length > 0) {
        writeResult("-1\t" + filterText)
      } else {
        return
      }
      hide()
      return
    }

    if (rowIndex < 0 || rowIndex >= filteredModel.count) return

    const it = filteredModel.get(rowIndex)

    if (it.kind === "chain-apps") { showApps(screenName); return }
    if (it.kind === "chain-power") { showPower(screenName); return }

    // Close the current overlay before spawning an action. Some actions open a
    // dmenu immediately; hiding afterward races with that new menu and can
    // leave only the full-screen layer visible.
    const kind = it.kind
    const payload = it.payload
    hide()
    runAction(kind, payload)
  }

  function cancelCurrent() {
    if (mode === "dmenu") writeResult("")
    hide()
  }

  function runAction(kind, payload) {
    switch (kind) {
      case "app": {
        const entry = DesktopEntries.byId(payload)
        if (entry) entry.execute()
        break
      }
      case "spawn":
        spawnProcess.exec(JSON.parse(payload))
        break
      case "power":
        runPower(payload)
        break
      case "window":
        Hyprland.dispatch("focuswindow address:" + payload)
        break
    }
  }

  ListModel { id: itemsModel }
  ListModel { id: filteredModel }

  Connections {
    target: DesktopEntries.applications

    function onValuesChanged() {
      if (root.visible && root.mode === "apps") root.populateApps()
    }
  }

  Process { id: spawnProcess }
  Process { id: powerProcess }
  Process { id: fifoWriter }
  Process {
    id: dmenuFileProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.populateDmenuItems(text)
    }
  }

  Process {
    id: clientsProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // The user may have opened a different menu in the ms it took
        // hyprctl to answer; don't append windows into that one.
        if (root.mode !== "windows") return
        if (text && text.trim()) {
          try {
            const clients = JSON.parse(text)
            if (Array.isArray(clients)) {
              for (let i = 0; i < clients.length; i++) {
                const client = clients[i]
                const title = client.title || client.initialTitle || client.class || "(untitled)"
                const wsName = client.workspace && client.workspace.name ? client.workspace.name : ""
                const sub = (client.class || "") + (wsName ? "  ·  " + wsName : "")
                root.addItem(title, sub, "window", client.address)
              }
            }
          } catch (e) {
            // leave items empty on parse failure
          }
        }
        root.refreshFiltered()
      }
    }
  }
}
