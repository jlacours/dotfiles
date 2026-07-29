import QtQuick

// Compact tray playback toggle. The icon is deliberately just the classic
// transport glyph: enough affordance for a taskbar, without competing with
// the clock or turning the notification area into a second player window.
Item {
  id: button

  width: 22
  height: 22
  opacity: MediaState.available ? 1 : 0.45

  Item {
    anchors.centerIn: parent
    anchors.horizontalCenterOffset: mouse.pressed ? 1 : 0
    anchors.verticalCenterOffset: mouse.pressed ? 1 : 0
    width: 12
    height: 12

    // Playing: pause bars. Paused or stopped: a crisp three-step triangle.
    Rectangle {
      visible: MediaState.playing
      x: 2; y: 2; width: 3; height: 8
      color: Win95Theme.text
    }
    Rectangle {
      visible: MediaState.playing
      x: 7; y: 2; width: 3; height: 8
      color: Win95Theme.text
    }
    Rectangle {
      visible: !MediaState.playing
      x: 2; y: 1; width: 2; height: 10
      color: Win95Theme.text
    }
    Rectangle {
      visible: !MediaState.playing
      x: 4; y: 3; width: 3; height: 6
      color: Win95Theme.text
    }
    Rectangle {
      visible: !MediaState.playing
      x: 7; y: 5; width: 3; height: 2
      color: Win95Theme.text
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: MediaState.available
    onClicked: {
      Win95MenuState.requestStartClose();
      MediaState.toggle();
    }
  }
}
