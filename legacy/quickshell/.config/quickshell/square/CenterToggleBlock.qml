import QtQuick

// On/off switches for the bar's four center-area modules, shown as nerd-font
// glyphs. Lives in the left cluster, right after the workspaces widget.
// Normal foreground while its module is shown, dim (textMuted) while hidden
// -- so a hidden module's toggle fades into the bar. The ticker (4th glyph)
// is exclusive: activating any status module (AI/tmux/vitals) leaves ticker
// mode, and vice versa. The ticker glyph is grouped behind a hairline
// divider. Left-click flips visibility through CenterModulesState, which
// persists the choice.
Row {
  id: root

  spacing: Theme.padSm
  height: Theme.barHeight

  Item {
    anchors.verticalCenter: parent.verticalCenter
    implicitHeight: Theme.barHeight
    implicitWidth: aiIcon.implicitWidth

    Text {
      id: aiIcon
      anchors.centerIn: parent
      text: "󰚩"
      color: (!CenterModulesState.news && CenterModulesState.aiUsage) ? Theme.foreground : Theme.textMuted
      font.family: Theme.iconFamily
      font.pixelSize: 13
    }

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Theme.padXs
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: CenterModulesState.toggle("aiUsage")
    }
  }

  Item {
    anchors.verticalCenter: parent.verticalCenter
    implicitHeight: Theme.barHeight
    implicitWidth: tmuxIcon.implicitWidth

    Text {
      id: tmuxIcon
      anchors.centerIn: parent
      text: ""
      color: (!CenterModulesState.news && CenterModulesState.tmux) ? Theme.foreground : Theme.textMuted
      font.family: Theme.iconFamily
      font.pixelSize: 13
    }

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Theme.padXs
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: CenterModulesState.toggle("tmux")
    }
  }

  Item {
    anchors.verticalCenter: parent.verticalCenter
    implicitHeight: Theme.barHeight
    implicitWidth: vitIcon.implicitWidth

    Text {
      id: vitIcon
      anchors.centerIn: parent
      text: "󰗶"
      color: (!CenterModulesState.news && CenterModulesState.vitals) ? Theme.foreground : Theme.textMuted
      font.family: Theme.iconFamily
      font.pixelSize: 13
    }

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Theme.padXs
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: CenterModulesState.toggle("vitals")
    }
  }

  // Hairline divider visually groups the status toggles apart from the ticker.
  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: Theme.hairline
    height: Theme.dividerHeight
    color: Theme.borderSubtle
  }

  // ── news ticker toggle ───────────────────────────────────────────
  Item {
    anchors.verticalCenter: parent.verticalCenter
    implicitHeight: Theme.barHeight
    implicitWidth: newsIcon.implicitWidth

    Text {
      id: newsIcon
      anchors.centerIn: parent
      text: "\uf1ea"
      color: CenterModulesState.news ? Theme.foreground : Theme.textMuted
      font.family: Theme.iconFamily
      font.pixelSize: Theme.fontLg
    }

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Theme.padXs
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: CenterModulesState.toggle("news")
    }
  }
}
