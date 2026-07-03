pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// RSS news-ticker state: fetches headlines via rss.sh, tracks the current
// item index, and provides next/prev/open helpers. Mirrors AiUsageState's
// Process + StdioCollector + Timer pattern.
Singleton {
  id: root

  readonly property string scriptPath:
    Quickshell.env("HOME") + "/.config/quickshell/scripts/rss.sh"

  property var items: []
  property int index: 0
  readonly property var current:
    (items.length && index >= 0 && index < items.length) ? items[index] : null
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
      index = 0
      ready = true
    } catch (e) {
      console.warn("RssState: failed to parse items JSON:", e)
    }
  }

  function next() {
    if (items.length > 0) index = (index + 1) % items.length
  }

  function prev() {
    if (items.length > 0) index = (index - 1 + items.length) % items.length
  }

  function openCurrent() {
    if (current && current.link) {
      opener.command = ["xdg-open", current.link]
      opener.running = true
    }
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

  // Auto-advance every 7 seconds whem there's content to rotate through.
  Timer {
    interval: 7000
    running: root.ready && items.length > 1
    repeat: true
    onTriggered: root.next()
  }

  Process {
    id: proc
    command: [root.scriptPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parse(text)
    }
  }

  // Lazy xdg-open process; configured per-call in openCurrent().
  Process {
    id: opener
  }
}
