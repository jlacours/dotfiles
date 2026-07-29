pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// SearXNG + gluetun VPN sidecar status for the bar.
//
// Backed by scripts/searxng-vpn.sh, which delegates `status` to the canonical
// ~/.local/bin/searxng-vpn-status.sh (KEY=value lines) and degrades to a clean
// "not-installed" set when the stack is absent. `toggle` start/stops the two
// user units; `logs` opens the combined journal. See SearxngVpnBlock.qml.
Singleton {
  id: root

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string scriptPath: home + "/.config/quickshell/scripts/searxng-vpn.sh"

  // Raw parsed fields (defaults mirror the not-installed set).
  property string overall: "not-installed"
  property string gluetunState: "missing"
  property string gluetunHealth: "missing"
  property string searxngState: "missing"
  property string searxngHttp: "error"
  property string vpnIp: "unavailable"
  property string tunnelStatus: "down"

  // Derived convenience for the Block.
  readonly property bool installed: root.overall !== "not-installed"
  readonly property bool ok: root.overall === "ok"
  readonly property bool degraded: root.installed && !root.ok

  function refresh() {
    if (statusProc.running) return
    statusProc.exec([root.scriptPath, "status"])
  }

  function toggle() {
    if (toggleProc.running) return
    toggleProc.exec([root.scriptPath, "toggle"])
  }

  function openLogs() {
    logsProc.exec([root.scriptPath, "logs"])
  }

  function parse(text) {
    if (!text || !text.trim()) return  // keep last known state on empty output
    const map = {}
    for (const line of text.split("\n")) {
      const idx = line.indexOf("=")
      if (idx <= 0) continue
      map[line.slice(0, idx).trim()] = line.slice(idx + 1).trim()
    }
    // Only overwrite keys the script actually emitted (a missing key means the
    // check was skipped/errored — keep the previous value).
    if ("OVERALL" in map) root.overall = map.OVERALL
    if ("GLUETUN_STATE" in map) root.gluetunState = map.GLUETUN_STATE
    if ("GLUETUN_HEALTH" in map) root.gluetunHealth = map.GLUETUN_HEALTH
    if ("SEARXNG_STATE" in map) root.searxngState = map.SEARXNG_STATE
    if ("SEARXNG_HTTP" in map) root.searxngHttp = map.SEARXNG_HTTP
    if ("VPN_IP" in map) root.vpnIp = map.VPN_IP
    if ("TUNNEL_STATUS" in map) root.tunnelStatus = map.TUNNEL_STATUS
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
  }

  Process {
    id: toggleProc
    onExited: root.refresh()
  }

  Process {
    id: logsProc
  }

  // gluetun health + a control-server curl are slow-ish; poll moderately. The
  // statusProc.running guard above absorbs overlaps when a check runs long.
  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
