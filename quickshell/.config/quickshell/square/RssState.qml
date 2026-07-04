pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// RSS news-ticker state: fetches headlines via rss.sh and exposes the parsed
// item list. The RssBlock widget owns the continuous marquee + segment logic
// and calls openLink() to launch an article. Mirrors AiUsageState's Process +
// StdioCollector + Timer pattern.
Singleton {
  id: root

  readonly property string scriptPath:
    Quickshell.env("HOME") + "/.config/quickshell/scripts/rss.sh"

  property var items: []
  property bool ready: false
  readonly property bool refreshing: proc.running

  function refresh() {
    if (!proc.running) proc.running = true
  }

  function parse(text) {
    if (!text || !text.trim()) return
    try {
      const a = JSON.parse(text)
      items = Array.isArray(a) ? a : []
      ready = true
    } catch (e) {
      console.warn("RssState: failed to parse items JSON:", e)
    }
  }

  // Launch an article link in the default browser.
  function openLink(link) {
    if (!link) return
    opener.command = ["xdg-open", link]
    opener.running = true
  }

  Component.onCompleted: refresh()

  // Poll for fresh items every 15 minutes.
  Timer {
    interval: 900000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Process {
    id: proc
    command: [root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
  }

  // Lazy xdg-open process; configured per-call in openLink().
  Process {
    id: opener
  }
}
