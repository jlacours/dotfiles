import QtQuick

// Tray-side on/off switches for the bar's three center modules, shown as
// nerd-font glyphs. Normal foreground while its module is shown, dim
// (textMuted) while hidden -- so a hidden module's toggle fades into the
// bar. Left-click
// flips visibility through CenterModulesState, which persists the choice.
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
      color: CenterModulesState.aiUsage ? Theme.foreground : Theme.textMuted
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
      color: CenterModulesState.tmux ? Theme.foreground : Theme.textMuted
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
      color: CenterModulesState.vitals ? Theme.foreground : Theme.textMuted
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
}
