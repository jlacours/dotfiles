import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

// All nine workspaces, always visible, grouped by monitor.
// State priority:
//   urgent-hidden -> focused -> active-visible -> active -> empty-visible -> empty
Row {
  id: root

  spacing: 0
  property var workspaceWindows: ({})
  property var appIconEntries: []
  property var svgs: ({})
  readonly property string home: Quickshell.env("HOME") || ""

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      Hyprland.refreshMonitors()
      Hyprland.refreshWorkspaces()

      const name = event.name
      if (name === "openwindow"
          || name === "closewindow"
          || name === "movewindow"
          || name === "movewindowv2") {
        root.refreshClients()
      }
    }
  }

  // Mirrors the workspace->monitor rules in hyprland.conf:
  // 1,2,3 -> HDMI-A-1 | 4,5,6 -> DP-2 | 7,8,9 -> DP-1
  readonly property var wsGroups: [[1, 2, 3], [4, 5, 6], [7, 8, 9]]

  readonly property var cells: {
    const out = []
    for (let g = 0; g < wsGroups.length; g++)
      for (let i = 0; i < wsGroups[g].length; i++)
        out.push({ id: wsGroups[g][i], newGroup: g > 0 && i === 0 })
    return out
  }

  readonly property var liveWorkspaces: Hyprland.workspaces.values
  readonly property var liveMonitors: Hyprland.monitors.values

  function appKeyForClient(client) {
    return String(client.class || client.title || "")
  }

  function iconsForWorkspace(workspaceId) {
    const apps = workspaceWindows[workspaceId] || []
    const counts = {}
    const compact = []

    for (let i = 0; i < apps.length; i++) {
      const icon = iconForApp(apps[i])
      if (!icon) continue
      if (!counts[icon]) {
        counts[icon] = 0
        compact.push({ icon: icon, count: 0 })
      }
      counts[icon] += 1
    }

    for (let i = 0; i < compact.length; i++) {
      compact[i].count = counts[compact[i].icon]
    }

    return compact.slice(0, 3)
  }

  function iconForApp(text) {
    const key = String(text || "").toLowerCase()
    if (!key) return ""

    for (let i = 0; i < appIconEntries.length; i++) {
      const entry = appIconEntries[i]
      const patterns = entry.patterns || []
      for (let j = 0; j < patterns.length; j++) {
        if (key.indexOf(patterns[j]) !== -1) {
          if (entry.icon) return entry.icon
          if (entry.svg) return "svg:" + entry.svg
          return ""
        }
      }
    }

    return "󰣆"
  }

  function isSvgRef(text) {
    return typeof text === "string" && text.indexOf("svg:") === 0
  }

  function svgUri(ref, color) {
    const name = isSvgRef(ref) ? ref.slice(4) : ref
    let svg = svgs[name] || ""
    if (!svg) return ""

    const r = Math.round(color.r * 255).toString(16).padStart(2, "0")
    const g = Math.round(color.g * 255).toString(16).padStart(2, "0")
    const b = Math.round(color.b * 255).toString(16).padStart(2, "0")
    svg = svg.replace(/currentColor/g, "#" + r + g + b)
    return "data:image/svg+xml;utf8," + encodeURIComponent(svg)
  }

  function loadAppIcons(text) {
    try {
      const data = JSON.parse(text || "[]")
      appIconEntries = Array.isArray(data) ? data : []
      refreshClients()
    } catch (e) {
      appIconEntries = []
    }
  }

  function loadSvgs() {
    svgLoader.exec(["python3", "-c",
      "import os, json, sys\n" +
      "d = sys.argv[1]\n" +
      "out = {}\n" +
      "if os.path.isdir(d):\n" +
      "    for f in os.listdir(d):\n" +
      "        if f.endswith('.svg'):\n" +
      "            try:\n" +
      "                with open(os.path.join(d, f)) as h: out[f] = h.read()\n" +
      "            except Exception: pass\n" +
      "print(json.dumps(out))",
      root.home + "/.config/quickshell/window-icons/svg"
    ])
  }

  function isVisibleWorkspace(workspaceId) {
    for (let i = 0; i < liveMonitors.length; i++) {
      const activeWorkspace = liveMonitors[i].activeWorkspace
      if (activeWorkspace && activeWorkspace.id === workspaceId)
        return true
    }

    return false
  }

  function isFocusedWorkspace(workspaceId) {
    for (let i = 0; i < liveMonitors.length; i++) {
      if (!liveMonitors[i].focused) continue

      const activeWorkspace = liveMonitors[i].activeWorkspace
      if (activeWorkspace && activeWorkspace.id === workspaceId)
        return true
    }

    return false
  }

  function workspaceState(urgent, focused, visible, occupied) {
    if (urgent && !visible) return "urgent-hidden"
    if (focused) return "focused"
    if (occupied && visible) return "active-visible"
    if (occupied) return "active"
    if (visible) return "empty-visible"
    return "empty"
  }

  function stateTextColor(state) {
    if (state === "urgent-hidden") return Theme.critical
    if (state === "focused" || state === "active-visible") return Theme.foreground
    if (state === "active") return Theme.textMuted
    if (state === "empty-visible") return Theme.text
    return Theme.textDim
  }

  function stateIconColor(state) {
    if (state === "urgent-hidden") return Theme.critical
    if (state === "focused" || state === "active-visible") return Theme.foreground
    if (state === "active") return Theme.textMuted
    if (state === "empty-visible") return Theme.text
    return Theme.textDim
  }

  function stateShowsStripe(state) {
    return state === "urgent-hidden"
      || state === "focused"
      || state === "active-visible"
      || state === "empty-visible"
  }

  function stateStripeColor(state) {
    if (state === "urgent-hidden") return Theme.critical
    if (state === "focused") return stateTextColor(state)
    return Theme.textDim
  }

  function refreshClients() {
    refreshTimer.restart()
  }

  Timer {
    id: refreshTimer
    interval: 120
    repeat: false
    onTriggered: {
      if (!clientsProcess.running) clientsProcess.exec(["hyprctl", "clients", "-j"])
    }
  }

  Timer {
    id: delayedRefreshTimer
    interval: 800
    repeat: false
    onTriggered: root.refreshClients()
  }

  Component.onCompleted: {
    loadSvgs()
    refreshClients()
    delayedRefreshTimer.start()
  }

  Repeater {
    model: root.cells

    Item {
      id: cell
      required property var modelData
      readonly property var ws: root.liveWorkspaces.find(w => w.id === modelData.id) ?? null
      readonly property bool visibleWorkspace: root.isVisibleWorkspace(modelData.id)
      readonly property bool focused: (ws ? ws.focused : false) || root.isFocusedWorkspace(modelData.id)
      readonly property bool urgent: ws ? ws.urgent === true : false
      readonly property var windowIcons: root.iconsForWorkspace(modelData.id)
      readonly property bool occupied: cell.windowIcons.length > 0 || (ws ? ws.toplevels.values.length > 0 : false)
      readonly property string state: root.workspaceState(cell.urgent, cell.focused, cell.visibleWorkspace, cell.occupied)
      readonly property int groupGap: modelData.newGroup ? Theme.padLg : 0
      readonly property int chipWidth: Math.max(18, content.implicitWidth + Theme.padSm * 2)
        + (focused ? Theme.padMd : visibleWorkspace ? Theme.padSm : 0)

      implicitWidth: cell.groupGap + cell.chipWidth
      implicitHeight: Theme.barHeight

      Behavior on implicitWidth {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }

      Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        x: cell.groupGap + Math.round((cell.chipWidth - implicitWidth) / 2)
        spacing: 3

        Behavior on x {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Text {
          id: label
          anchors.verticalCenter: parent.verticalCenter
          text: String(cell.modelData.id)
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSm
          font.bold: cell.focused
          color: root.stateTextColor(cell.state)

          Behavior on color {
            ColorAnimation { duration: Theme.animFast }
          }
        }

        Repeater {
          model: cell.windowIcons

          Item {
            required property var modelData
            readonly property bool isSvg: root.isSvgRef(modelData.icon)
            readonly property color iconColor: root.stateIconColor(cell.state)
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: (isSvg ? iconImage.width : iconLabel.implicitWidth) + (countLabel.visible ? countLabel.implicitWidth + 1 : 0)
            implicitHeight: Math.max(isSvg ? iconImage.height : iconLabel.implicitHeight, countLabel.visible ? countLabel.implicitHeight + 1 : 0)

            Text {
              id: iconLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              visible: !parent.isSvg
              text: parent.isSvg ? "" : modelData.icon
              color: parent.iconColor
              font.family: Theme.iconFamily
              font.pixelSize: 10
            }

            Image {
              id: iconImage
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              visible: parent.isSvg
              width: 10
              height: 10
              sourceSize.width: 10
              sourceSize.height: 10
              source: parent.isSvg ? root.svgUri(modelData.icon, parent.iconColor) : ""
              asynchronous: true
            }

            Text {
              id: countLabel
              anchors.left: parent.isSvg ? iconImage.right : iconLabel.right
              anchors.leftMargin: 1
              anchors.top: parent.top
              anchors.topMargin: -2
              visible: modelData.count > 1
              text: modelData.count
              color: parent.iconColor
              font.family: Theme.fontFamily
              font.pixelSize: 8
              font.bold: true
            }
          }
        }
      }

      Rectangle {
        visible: root.stateShowsStripe(cell.state)
        anchors.bottom: parent.bottom
        x: cell.groupGap
        width: cell.chipWidth
        height: Theme.stripe + 1
        color: root.stateStripeColor(cell.state)

        Behavior on color {
          ColorAnimation { duration: Theme.animFast }
        }

        Behavior on x {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Behavior on width {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: Hyprland.dispatch("workspace " + cell.modelData.id)
      }
    }
  }

  Process {
    id: clientsProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!text || !text.trim()) {
          root.workspaceWindows = ({})
          return
        }

        try {
          const clients = JSON.parse(text)
          const next = {}
          if (Array.isArray(clients)) {
            for (let i = 0; i < clients.length; i++) {
              const client = clients[i]
              const workspaceId = client.workspace && typeof client.workspace.id === "number" ? client.workspace.id : 0
              if (workspaceId < 1) continue
              if (!next[workspaceId]) next[workspaceId] = []
              next[workspaceId].push(root.appKeyForClient(client))
            }
          }
          root.workspaceWindows = next
        } catch (e) {
          root.workspaceWindows = ({})
        }
      }
    }
  }

  Process {
    id: svgLoader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.svgs = JSON.parse(text || "{}")
          root.refreshClients()
        } catch (e) {
          root.svgs = ({})
        }
      }
    }
  }

  FileView {
    path: root.home + "/.config/quickshell/window-icons/apps.json"
    watchChanges: true
    onLoaded: root.loadAppIcons(text())
    onFileChanged: {
      reload()
      root.loadAppIcons(text())
      root.loadSvgs()
    }
  }
}
