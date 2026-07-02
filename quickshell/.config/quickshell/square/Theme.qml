pragma Singleton

import QtQuick
import "wallust.js" as Wallust

QtObject {
  id: theme

  // Colors — semantic (from wallust)
  readonly property color bg: Wallust.bg
  readonly property color surface: Wallust.surfaceElevated
  readonly property color border: Wallust.border
  readonly property color borderActive: Wallust.borderActive
  readonly property color foreground: Wallust.foreground
  readonly property color text: Wallust.text
  readonly property color textMuted: Wallust.textMuted
  readonly property color textDim: Wallust.textDim
  readonly property color accent: Wallust.accentPrimary
  readonly property color accentAlt: Wallust.accentAlt
  readonly property color critical: Wallust.critical
  readonly property color success: Wallust.success
  readonly property color warning: Wallust.warning
  readonly property color info: Wallust.info

  // Presentation surfaces — translucent without weakening semantic base colors.
  function withAlpha(baseColor, alpha) {
    return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, alpha)
  }

  readonly property color barSurface: withAlpha(bg, 0.82)
  readonly property color panelSurface: withAlpha(surface, 0.90)
  readonly property color cardSurface: withAlpha(surface, 0.66)
  readonly property color controlSurface: withAlpha(bg, 0.54)
  readonly property color borderSubtle: withAlpha(border, 0.48)

  // Typography
  readonly property string fontFamily: "Comic Code"
  readonly property string iconFamily: "Symbols Nerd Font Mono"
  readonly property int fontSm: 10
  readonly property int fontMd: 11
  readonly property int fontLg: 13

  // Spacing
  readonly property int padXs: 2
  readonly property int padSm: 4
  readonly property int padMd: 8
  readonly property int padLg: 12
  readonly property int panelPadding: 12
  readonly property int panelGap: 10

  // Brutalist: zero radius, everywhere.
  readonly property int radius: 0

  // Strokes
  readonly property int hairline: 1
  readonly property int stripe: 2
  readonly property int dividerHeight: 8

  // Bar geometry
  readonly property int barHeight: 28

  // Right-side module gap (swaybar-like generous spacing)
  readonly property int gapLg: 18

  // Animation — keep snappy, near-instant
  readonly property int animFast: 80

  // Per-monitor accent colours, keyed by Hyprland monitor id (0-based).
  // id 0 -> accent, id 1 -> accentAlt, id 2 -> info, 4th+ -> success
  readonly property var monitorAccents: [accent, accentAlt, info, success]

  function monitorAccent(monitorId) {
    return monitorAccents[monitorId % monitorAccents.length]
  }
}
