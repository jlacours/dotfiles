import QtQuick
import Quickshell
import Quickshell.Wayland

// Detail panel for AiUsageBlock. One content-sized overlay window per screen,
// anchored top-right (the same layout NotificationPopups uses, which renders
// correctly on fractional-scale outputs — a full-screen window with an
// anchored child does not). Tabs switch providers in place; click a bar tag
// again to dismiss.
Scope {
  readonly property var tabs: [
    { id: "claude",     label: "CLAUDE" },
    { id: "codex",      label: "CHATGPT" },
    { id: "zai",        label: "Z.AI" },
    { id: "openrouter", label: "OR" }
  ]

  function sevColor(pct) {
    if (pct === undefined || pct === null || pct < 0) return Theme.accent
    if (pct >= 90) return Theme.critical
    if (pct >= 70) return Theme.warning
    return Theme.accent
  }

  // Detail rows for the selected provider: { label, value, pct, sub, barColor? }.
  // pct < 0 means "no usage bar for this row".
  function rowsFor(sel) {
    const c = AiUsageState.claude
    const x = AiUsageState.codex
    const z = AiUsageState.zai

    if (sel === "claude") {
      if (!c.ok)
        return [{ label: "usage", value: "n/a", pct: -1, sub: "run Claude Code to refresh its token" }]
      return [
        { label: "5-hour", value: (c.pct5h != null ? Math.round(c.pct5h) + "%" : "--"),
          pct: (c.pct5h != null ? c.pct5h : -1),
          sub: "resets in " + AiUsageState.resetIn(c.reset5h) },
        { label: "weekly", value: (c.pctWeek != null ? Math.round(c.pctWeek) + "%" : "--"),
          pct: (c.pctWeek != null ? c.pctWeek : -1),
          sub: "resets in " + AiUsageState.resetIn(c.resetWeek) },
        { label: "5h spend", value: (c.cost != null ? "$" + c.cost.toFixed(2) : "--"), pct: -1,
          sub: (c.tokens != null ? AiUsageState.fmtTokens(c.tokens) + " tokens" : "") },
        { label: "projected", value: (c.projCost != null ? "$" + c.projCost.toFixed(2) : "--"), pct: -1,
          sub: (c.projTokens != null ? AiUsageState.fmtTokens(c.projTokens) + " tokens by reset" : "") },
        { label: "burn rate", value: (c.burnPerHour != null ? "$" + c.burnPerHour.toFixed(2) + "/h" : "--"), pct: -1,
          sub: ((c.remainingMin != null ? c.remainingMin + " min left" : "")
              + ((c.models && c.models.length) ? "  ·  " + c.models.join(", ") : "")) }
      ]
    }

    if (sel === "codex") {
      if (!x.ok)
        return [{ label: "rate limits", value: "n/a", pct: -1, sub: "run Codex once to populate" }]
      return [
        { label: "5-hour", value: Math.round(x.pct5h) + "%", pct: x.pct5h,
          sub: "resets in " + AiUsageState.resetIn(x.reset5h) },
        { label: "weekly", value: Math.round(x.pctWeek) + "%", pct: x.pctWeek,
          sub: "resets in " + AiUsageState.resetIn(x.resetWeek) },
        { label: "plan", value: (x.plan || "?"), pct: -1,
          sub: (x.asOf ? "updated " + AiUsageState.ago(x.asOf) : "") }
      ]
    }

    if (sel === "openrouter") {
      const o = AiUsageState.openrouter
      if (!o.ok)
        return [{ label: "credits", value: "n/a", pct: -1, sub: "OpenRouter API unreachable" }]
      return [
        { label: "remaining", value: "$" + o.remaining.toFixed(2),
          pct: (o.pctRemaining != null ? o.pctRemaining : -1),
          barColor: (o.pctRemaining != null ? sevColor(100 - o.pctRemaining) : undefined),
          sub: "of $" + o.total.toFixed(2) + " purchased" },
        { label: "used total", value: "$" + o.used.toFixed(2), pct: -1,
          sub: (o.pctRemaining != null ? Math.round(o.pctRemaining) + "% left" : "") },
        { label: "this key", value: (o.keyUsage != null ? "$" + o.keyUsage.toFixed(2) : "--"), pct: -1,
          sub: ((o.keyMonthly != null ? "mo $" + o.keyMonthly.toFixed(2) : "")
              + (o.keyWeekly != null ? "   wk $" + o.keyWeekly.toFixed(2) : "")) }
      ]
    }

    if (!z.ok)
      return [{ label: "quota", value: "n/a", pct: -1, sub: "z.ai API unreachable" }]
    return [
      { label: "5-hour tokens", value: Math.round(z.pct5h) + "%", pct: z.pct5h,
        sub: "resets in " + AiUsageState.resetIn(z.reset5h) },
      { label: "weekly tokens", value: Math.round(z.pctWeek) + "%", pct: z.pctWeek,
        sub: "resets in " + AiUsageState.resetIn(z.resetWeek) },
      { label: "monthly MCP", value: Math.round(z.mcpPct) + "%", pct: z.mcpPct,
        sub: "resets in " + AiUsageState.resetIn(z.mcpReset) }
    ]
  }

  function metaFor(sel) {
    if (sel === "claude") return "Claude" + (AiUsageState.claude.plan ? " · " + AiUsageState.claude.plan : "")
    if (sel === "codex")  return "Codex" + (AiUsageState.codex.plan ? " · " + AiUsageState.codex.plan : "")
    if (sel === "openrouter") return "OpenRouter · prepaid credits"
    return "GLM coding plan" + (AiUsageState.zai.level ? " · " + AiUsageState.zai.level : "")
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panelWindow
      required property var modelData
      readonly property bool activeScreen: AiUsageState.panelScreenName === modelData.name

      screen: modelData
      WlrLayershell.namespace: "quickshell-square-ai-usage-" + (modelData ? modelData.name : "default")
      WlrLayershell.layer: WlrLayer.Overlay
      color: "transparent"
      exclusiveZone: 0
      visible: AiUsageState.panelVisible && activeScreen
      implicitWidth: 320
      implicitHeight: panel.implicitHeight
      mask: Region { item: panel }

      anchors {
        top: true
        right: true
      }

      margins {
        top: Theme.barHeight + Theme.padMd
        right: Theme.padMd
      }

      Rectangle {
        id: panel
        anchors.top: parent.top
        anchors.right: parent.right
        width: 320
        implicitHeight: content.implicitHeight + Theme.panelPadding * 2
        height: implicitHeight
        color: Theme.panelSurface
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        Column {
          id: content
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Theme.panelPadding
          spacing: Theme.panelGap

          // Header: title + provider tabs.
          Row {
            width: parent.width
            spacing: Theme.padMd

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "AI USAGE"
              color: Theme.textMuted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSm
              font.bold: true
            }

            Item { width: 1; height: 1 }

            Repeater {
              model: tabs

              Text {
                required property var modelData
                readonly property bool sel: AiUsageState.selected === modelData.id
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                color: sel ? Theme.accent : (tabArea.containsMouse ? Theme.text : Theme.textDim)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSm
                font.bold: true

                MouseArea {
                  id: tabArea
                  anchors.fill: parent
                  anchors.margins: -Theme.padXs
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: AiUsageState.selected = modelData.id
                }
              }
            }
          }

          Text {
            width: parent.width
            text: (AiUsageState.data, metaFor(AiUsageState.selected))
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSm
            elide: Text.ElideRight
          }

          Rectangle {
            width: parent.width
            height: Theme.hairline
            color: Theme.borderSubtle
          }

          // Detail rows. The leading reads of `now`/`data` are dependency hooks
          // so rows re-evaluate as usage refreshes and countdowns tick.
          Repeater {
            model: (AiUsageState.now, AiUsageState.data, rowsFor(AiUsageState.selected))

            Item {
              required property var modelData
              width: content.width
              implicitHeight: rowCol.implicitHeight

              Column {
                id: rowCol
                width: parent.width
                spacing: Theme.padXs

                Item {
                  width: parent.width
                  height: valueText.implicitHeight

                  Text {
                    id: labelText
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSm
                  }

                  Text {
                    id: valueText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.value
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontMd
                    font.bold: true
                  }
                }

                // Usage bar (only for percentage rows).
                Rectangle {
                  width: parent.width
                  height: 4
                  visible: modelData.pct >= 0
                  color: Theme.border

                  Rectangle {
                    height: parent.height
                    width: parent.width * Math.max(0, Math.min(1, (modelData.pct || 0) / 100))
                    color: (modelData.barColor !== undefined ? modelData.barColor : sevColor(modelData.pct))
                  }
                }

                Text {
                  width: parent.width
                  visible: modelData.sub !== ""
                  text: modelData.sub
                  color: Theme.textDim
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSm
                  elide: Text.ElideRight
                }
              }
            }
          }
        }
      }
    }
  }
}
