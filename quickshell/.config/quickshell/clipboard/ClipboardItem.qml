import QtQuick
import "../wallust.js" as Wallust
import "." as Clipboard

Rectangle {
  id: root

  required property int sourceIndex
  required property string preview
  required property bool isImage
  required property string imagePath
  property bool selected: false

  property bool hovered: hoverArea.containsMouse
  readonly property color surfaceBase: Wallust.surfaceElevated
  readonly property color borderBase: Wallust.border
  readonly property color softSurface: Qt.rgba(surfaceBase.r, surfaceBase.g, surfaceBase.b, 0.62)
  readonly property color borderSubtle: Qt.rgba(borderBase.r, borderBase.g, borderBase.b, 0.48)

  color: root.softSurface
  border.width: 1
  border.color: (selected || hovered) ? Wallust.accentPrimary : root.borderSubtle
  implicitHeight: content.implicitHeight + 24
  height: implicitHeight

  MouseArea {
    id: hoverArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onClicked: Clipboard.ClipboardState.select(root.sourceIndex)
  }

  Column {
    id: content
    anchors.fill: parent
    anchors.margins: 12
    anchors.rightMargin: 36
    spacing: 6

    Image {
      width: parent.width
      height: 120
      visible: root.isImage && root.imagePath !== ""
      source: root.imagePath !== "" ? ("file://" + root.imagePath) : ""
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }

    Text {
      width: parent.width
      text: root.preview
      color: root.isImage ? Wallust.textMuted : Wallust.text
      font.family: "Comic Code"
      font.pixelSize: 11
      wrapMode: Text.Wrap
      maximumLineCount: root.isImage ? 1 : 3
      elide: Text.ElideRight
    }
  }

  Rectangle {
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: 8
    anchors.rightMargin: 8
    width: 18
    height: 18
    visible: root.hovered
    color: "transparent"
    border.width: 1
    border.color: root.borderSubtle

    Text {
      anchors.centerIn: parent
      text: "󰅖"
      color: Wallust.text
      font.family: "Symbols Nerd Font Mono"
      font.pixelSize: 10
    }

    MouseArea {
      anchors.fill: parent
      onClicked: Clipboard.ClipboardState.deleteEntry(root.sourceIndex)
    }
  }
}
