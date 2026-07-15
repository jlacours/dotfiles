import QtQuick

// Classic Win95 3D chrome. Raised: 1px white top/left, 1px black outer +
// 1px #808080 inner bottom/right. `pressed` inverts it (sunken button).
// `thin` draws the 1px status-well bevel (tray, status fields) instead.
Rectangle {
  id: bevel
  property bool pressed: false
  property bool thin: false

  color: Win95Theme.face

  // Win95 controls use two square edge layers: highlight/shadow inside a
  // white/black outer frame. Pressed controls reverse the light source.
  Rectangle {
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: 1
    color: bevel.thin
      ? Win95Theme.edgeShadow
      : (bevel.pressed ? Win95Theme.edgeDark : Win95Theme.edgeLight)
  }
  Rectangle {
    anchors { top: parent.top; left: parent.left; bottom: parent.bottom }
    width: 1
    color: bevel.thin
      ? Win95Theme.edgeShadow
      : (bevel.pressed ? Win95Theme.edgeDark : Win95Theme.edgeLight)
  }

  // Outer bottom/right edge.
  Rectangle {
    anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
    height: 1
    color: bevel.thin
      ? Win95Theme.edgeLight
      : (bevel.pressed ? Win95Theme.edgeLight : Win95Theme.edgeDark)
  }
  Rectangle {
    anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
    width: 1
    color: bevel.thin
      ? Win95Theme.edgeLight
      : (bevel.pressed ? Win95Theme.edgeLight : Win95Theme.edgeDark)
  }

  Rectangle {
    visible: !bevel.thin
    anchors {
      top: parent.top; left: parent.left; right: parent.right
      topMargin: 1; leftMargin: 1; rightMargin: 1
    }
    height: 1
    color: bevel.pressed
      ? Win95Theme.edgeShadow
      : Win95Theme.edgeMidLight
  }
  Rectangle {
    visible: !bevel.thin
    anchors {
      top: parent.top; left: parent.left; bottom: parent.bottom
      topMargin: 1; leftMargin: 1; bottomMargin: 1
    }
    width: 1
    color: bevel.pressed
      ? Win95Theme.edgeShadow
      : Win95Theme.edgeMidLight
  }
  Rectangle {
    visible: !bevel.thin
    anchors {
      left: parent.left; right: parent.right; bottom: parent.bottom
      leftMargin: 1; rightMargin: 1; bottomMargin: 1
    }
    height: 1
    color: bevel.pressed
      ? Win95Theme.edgeMidLight
      : Win95Theme.edgeShadow
  }
  Rectangle {
    visible: !bevel.thin
    anchors {
      top: parent.top; right: parent.right; bottom: parent.bottom
      topMargin: 1; rightMargin: 1; bottomMargin: 1
    }
    width: 1
    color: bevel.pressed
      ? Win95Theme.edgeMidLight
      : Win95Theme.edgeShadow
  }
}
