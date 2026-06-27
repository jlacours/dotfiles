import QtQuick

// Icon + percentage. Scroll changes volume, left-click opens the rate menu,
// and right-click toggles mute.
Item {
  id: root

  required property string screenName

  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.padSm

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: VolumeState.deviceIcon
      color: VolumeState.muted ? Theme.textDim
        : AudioRateState.panelVisible && AudioRateState.panelScreenName === root.screenName
          ? Theme.accent : Theme.text
      font.family: Theme.iconFamily
      font.pixelSize: Theme.fontLg
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: (VolumeState.muted ? "MUTE" : VolumeState.volume + "%")
      color: VolumeState.muted ? Theme.textDim : Theme.text
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontMd
      font.bold: true
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) {
        VolumeState.toggleMute()
      } else {
        AudioRateState.toggle(root.screenName)
      }
    }

    onWheel: wheel => {
      const step = 5
      let target = VolumeState.volume
      if (wheel.angleDelta.y > 0) {
        target = Math.min(target + step, 100)
      } else if (wheel.angleDelta.y < 0) {
        target = Math.max(target - step, 0)
      }
      VolumeState.setVolume(target)
    }
  }
}
