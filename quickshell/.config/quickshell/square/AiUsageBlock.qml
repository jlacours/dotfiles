import QtQuick

// Four clickable AI-usage tags. Window providers (CLD/GPT/ZAI) show
// "5h% / week%"; OpenRouter (OR) shows remaining prepaid credit ("$83.16").
// Clicking a tag expands its detail in AiUsagePanel.
Item {
  id: root

  required property string screenName

  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  function sevColor(pct) {
    if (pct === undefined || pct === null || pct < 0) return Theme.text
    if (pct >= 90) return Theme.critical
    if (pct >= 70) return Theme.warning
    return Theme.text
  }

  // "12%" or em-dash when a window isn't reported.
  function pp(p) {
    return (p === undefined || p === null) ? "—" : Math.round(p) + "%"
  }

  // Worst of the two windows, for the segment's colour.
  function worst(a, b) {
    const x = (a === undefined || a === null) ? -1 : a
    const y = (b === undefined || b === null) ? -1 : b
    return Math.max(x, y)
  }

  // colorPct is a "higher = worse" number driving the segment colour.
  readonly property var segments: [
    {
      id: "claude", tag: "CLD",
      text: pp(AiUsageState.claude.pct5h) + " / " + pp(AiUsageState.claude.pctWeek),
      colorPct: worst(AiUsageState.claude.pct5h, AiUsageState.claude.pctWeek)
    },
    {
      id: "codex", tag: "GPT",
      text: pp(AiUsageState.codex.pct5h) + " / " + pp(AiUsageState.codex.pctWeek),
      colorPct: worst(AiUsageState.codex.pct5h, AiUsageState.codex.pctWeek)
    },
    {
      id: "zai", tag: "ZAI",
      text: pp(AiUsageState.zai.pct5h) + " / " + pp(AiUsageState.zai.pctWeek),
      colorPct: worst(AiUsageState.zai.pct5h, AiUsageState.zai.pctWeek)
    },
    {
      id: "openrouter", tag: "OR",
      text: AiUsageState.openrouter.ok ? ("$" + AiUsageState.openrouter.remaining.toFixed(2)) : "—",
      colorPct: (AiUsageState.openrouter.ok && AiUsageState.openrouter.pctRemaining != null)
        ? (100 - AiUsageState.openrouter.pctRemaining) : -1
    }
  ]

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.padMd

    Repeater {
      model: root.segments

      Item {
        id: seg
        required property var modelData
        readonly property bool active: AiUsageState.panelVisible && AiUsageState.selected === modelData.id

        anchors.verticalCenter: parent.verticalCenter
        implicitHeight: Theme.barHeight
        implicitWidth: segRow.implicitWidth

        Row {
          id: segRow
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.padSm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: seg.modelData.tag
            color: seg.active ? Theme.accent : Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSm
            font.bold: true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: seg.modelData.text
            color: root.sevColor(seg.modelData.colorPct)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontMd
            font.bold: true
          }
        }

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Theme.padXs
          cursorShape: Qt.PointingHandCursor
          onClicked: AiUsageState.toggle(seg.modelData.id, root.screenName)
        }
      }
    }
  }
}
