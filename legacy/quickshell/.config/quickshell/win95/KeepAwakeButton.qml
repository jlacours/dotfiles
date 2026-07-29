import QtQuick

// Tray-well keep-awake toggle: a tiny CRT whose screen stays lit while the
// idle-inhibit lock is held. Latched state renders sunken, exactly like a
// toggled Win95 toolbar button.
BevelRect {
  id: chip

  width: 22
  height: 22
  pressed: KeepAwakeState.inhibited || mouse.pressed

  // 16x16 monitor drawn from squares; keeps the tray pixel-crisp with no
  // font-glyph approximation.
  Item {
    width: 16
    height: 16
    anchors.centerIn: parent
    // Nudge only during a physical press; a latched button keeps its
    // glyph centered (real Win95 toolbar behavior).
    anchors.horizontalCenterOffset: mouse.pressed ? 1 : 0
    anchors.verticalCenterOffset: mouse.pressed ? 1 : 0

    Rectangle {
      x: 1; y: 2; width: 14; height: 9
      color: Win95Theme.face
      border.color: Win95Theme.edgeDark
      border.width: 1

      // Screen: desktop teal while keep-awake is on, powered-down otherwise.
      Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        color: KeepAwakeState.inhibited
          ? Win95Theme.desktop
          : Win95Theme.edgeShadow
      }
    }
    Rectangle { x: 6; y: 11; width: 4; height: 2; color: Win95Theme.edgeShadow }
    Rectangle { x: 4; y: 13; width: 8; height: 1; color: Win95Theme.edgeDark }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    onClicked: {
      Win95MenuState.requestStartClose();
      KeepAwakeState.toggle();
    }
  }
}
