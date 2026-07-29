import QtQuick
import "../wallust.js" as Wallust

// One row in the centered menu overlay. Mirrors clipboard/ClipboardItem.qml's
// shape (hover/selected border, click to activate).
//
// Styling note: this imports wallust.js directly (like clipboard/keybinds do)
// rather than square/Theme.qml. Quickshell keys its pragma-Singleton registry
// by each singleton's own resolved URL; a plain relative `import
// "../Theme.qml"` from a shared/symlinked directory does not reliably resolve
// to the *same* registered instance square's own files get via qmldir
// (verified against quickshell's source via deepwiki) — worst case it either
// silently constructs a redundant instance or fails to load. wallust.js is a
// `.pragma library` JS file instead, which Qt shares engine-wide regardless
// of import path, so this is the safe, already-proven pattern in this repo.
// The non-palette tokens below (font family/sizes, spacing, hairline) are
// literal copies of square/Theme.qml's current values for visual parity —
// see quickshell/AGENTS.md.
Rectangle {
  id: root

  required property int index
  required property string text
  required property string sub
  property bool selected: false

  property bool hovered: hoverArea.containsMouse
  readonly property color surfaceBase: Wallust.surfaceElevated
  readonly property color softSurface: Qt.rgba(surfaceBase.r, surfaceBase.g, surfaceBase.b, 0.62)

  signal activated()

  color: root.selected ? root.softSurface : "transparent"
  border.width: 1
  border.color: (root.selected || root.hovered) ? Wallust.accentPrimary : "transparent"
  implicitHeight: content.implicitHeight + 20

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onClicked: root.activated()
  }

  Column {
    id: content
    anchors.fill: parent
    anchors.margins: 10
    spacing: 4

    Text {
      width: parent.width
      text: root.text
      color: root.selected ? Wallust.accentPrimary : Wallust.text
      font.family: "Comic Code"
      font.pixelSize: 11
      font.bold: root.selected
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      visible: root.sub.length > 0
      text: root.sub
      color: Wallust.textMuted
      font.family: "Comic Code"
      font.pixelSize: 10
      elide: Text.ElideRight
    }
  }
}
