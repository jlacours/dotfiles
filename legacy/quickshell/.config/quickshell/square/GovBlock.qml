import QtQuick

// CPU governor mode indicator: "GOV PERF" (accent) / "GOV PWR" (muted).
// The mode sits in a fixed-width slot so toggling never nudges its neighbours.
// Left-click toggles performance <-> powersave via GovernorState (pkexec).
Item {
  id: root

  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  function modeLabel(g) {
    if (g === "performance") return "PERF"
    if (g === "powersave") return "PWR"
    if (g === "") return "…"
    return g.toUpperCase()
  }

  TextMetrics {
    id: modeMetrics
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontMd
    font.bold: true
    text: "PERF"
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.padSm

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "GOV"
      color: Theme.textMuted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSm
      font.bold: true
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: modeMetrics.width
      horizontalAlignment: Text.AlignLeft
      text: root.modeLabel(GovernorState.governor)
      color: GovernorState.performance ? Theme.accent : Theme.textMuted
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontMd
      font.bold: true
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    onClicked: GovernorState.toggle()
  }
}
