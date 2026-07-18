import Quickshell.Io
import QtQuick

// Flat notification-area volume control: wheel changes volume by 5%,
// left-click mutes, and right-click opens the full PipeWire mixer.
Item {
  id: button

  width: 43
  height: 22

  Row {
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: mouse.pressed ? 1 : 0
    anchors.verticalCenterOffset: mouse.pressed ? 1 : 0
    spacing: 2

    // Tiny pixel speaker, keeping the tray icon independent of icon fonts.
    Item {
      anchors.verticalCenter: parent.verticalCenter
      width: 15
      height: 16

      Rectangle { x: 1; y: 6; width: 4; height: 5; color: Win95Theme.text }
      Rectangle { x: 5; y: 5; width: 2; height: 7; color: Win95Theme.text }
      Rectangle { x: 7; y: 3; width: 2; height: 11; color: Win95Theme.text }
      Rectangle {
        x: 11; y: 6; width: 1; height: 5
        visible: VolumeState.available && !VolumeState.muted && VolumeState.percent > 0
        color: Win95Theme.text
      }
      Rectangle {
        x: 10; y: 5; width: 1; height: 1
        visible: VolumeState.available && !VolumeState.muted && VolumeState.percent > 0
        color: Win95Theme.text
      }
      Rectangle {
        x: 10; y: 11; width: 1; height: 1
        visible: VolumeState.available && !VolumeState.muted && VolumeState.percent > 0
        color: Win95Theme.text
      }
      Rectangle {
        x: 14; y: 4; width: 1; height: 8
        visible: VolumeState.available && !VolumeState.muted && VolumeState.percent >= 50
        color: Win95Theme.text
      }
      Rectangle {
        x: 13; y: 3; width: 1; height: 1
        visible: VolumeState.available && !VolumeState.muted && VolumeState.percent >= 50
        color: Win95Theme.text
      }
      Rectangle {
        x: 13; y: 12; width: 1; height: 1
        visible: VolumeState.available && !VolumeState.muted && VolumeState.percent >= 50
        color: Win95Theme.text
      }

      // Unrotated pixel blocks keep the muted X crisp at fractional scale.
      Item {
        x: 9; y: 4; width: 7; height: 9
        visible: !VolumeState.available || VolumeState.muted

        Rectangle { x: 1; y: 1; width: 2; height: 2; color: Win95Theme.alert }
        Rectangle { x: 5; y: 1; width: 2; height: 2; color: Win95Theme.alert }
        Rectangle { x: 3; y: 3; width: 2; height: 2; color: Win95Theme.alert }
        Rectangle { x: 1; y: 5; width: 2; height: 2; color: Win95Theme.alert }
        Rectangle { x: 5; y: 5; width: 2; height: 2; color: Win95Theme.alert }
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      width: 26
      horizontalAlignment: Text.AlignLeft
      text: !VolumeState.available ? "--" : VolumeState.muted ? "MUTE" : VolumeState.percent + "%"
      color: Win95Theme.text
      font.family: "Comic Code"
      font.pixelSize: 10
    }
  }

  Process {
    id: mixer
    command: ["pavucontrol"]
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: (event) => {
      Win95MenuState.requestStartClose();
      if (event.button === Qt.RightButton)
        mixer.running = true;
      else
        VolumeState.toggleMute();
    }

    onWheel: (event) => {
      Win95MenuState.requestStartClose();
      VolumeState.adjust(event.angleDelta.y / 120);
      event.accepted = true;
    }
  }
}
