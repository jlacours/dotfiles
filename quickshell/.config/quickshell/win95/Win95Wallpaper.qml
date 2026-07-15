import Quickshell
import QtQuick
import QtQuick.Controls

// Windows 95 Display Properties, Background page. Labwc supplies the real
// window titlebar and close control; QML owns only the classic client area.
Scope {
  id: root

  readonly property var placementKeys: [
    "fill", "fit", "center", "tile", "stretch"
  ]

  function previewFillMode(): int {
    switch (Win95WallpaperState.selectedPlacement) {
    case "fit": return Image.PreserveAspectFit;
    case "center": return Image.Pad;
    case "tile": return Image.Tile;
    case "stretch": return Image.Stretch;
    default: return Image.PreserveAspectCrop;
    }
  }

  component DialogButton: BevelRect {
    id: button
    property string label: ""
    property bool defaultButton: false
    signal clicked()

    width: 88
    height: 28
    pressed: buttonMouse.pressed

    Rectangle {
      anchors {
        fill: parent
        margins: 4
      }
      color: "transparent"
      border.width: button.defaultButton ? 1 : 0
      border.color: Win95Theme.text
    }

    Text {
      anchors.centerIn: parent
      text: button.label
      color: Win95Theme.text
      font.family: "Comic Code"
      font.pixelSize: 11
      renderType: Text.NativeRendering
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      onClicked: button.clicked()
    }
  }

  Variants {
    model: Quickshell.screens

    FloatingWindow {
      id: wallpaperWindow
      required property var modelData

      readonly property bool requestedVisible: Win95WallpaperState.visible
        && Win95WallpaperState.screenName === modelData.name

      screen: modelData
      title: "Display Properties"
      color: Win95Theme.face
      visible: requestedVisible
      implicitWidth: Math.min(620, modelData.width - 48)
      implicitHeight: Math.min(500, modelData.height - 80)

      onVisibleChanged: {
        if (visible) {
          wallpaperList.positionViewAtIndex(
            Win95WallpaperState.selectedIndex,
            ListView.Contain
          );
        } else if (requestedVisible) {
          Win95WallpaperState.cancel();
        }
      }

      Shortcut {
        sequence: "Escape"
        enabled: wallpaperWindow.visible
        onActivated: Win95WallpaperState.cancel()
      }

      Shortcut {
        sequence: "Return"
        enabled: wallpaperWindow.visible
        onActivated: Win95WallpaperState.accept()
      }

      Shortcut {
        sequence: "Down"
        enabled: wallpaperWindow.visible
        onActivated: Win95WallpaperState.moveSelection(1)
      }

      Shortcut {
        sequence: "Up"
        enabled: wallpaperWindow.visible
        onActivated: Win95WallpaperState.moveSelection(-1)
      }

      Column {
        anchors {
          fill: parent
          margins: 10
        }
        spacing: 8

        // The selected property-sheet tab sits over the page border.
        BevelRect {
          width: 108
          height: 27

          Text {
            anchors.centerIn: parent
            text: "Background"
            color: Win95Theme.text
            font.family: "Comic Code"
            font.pixelSize: 11
            renderType: Text.NativeRendering
          }
        }

        BevelRect {
          thin: true
          pressed: true
          width: parent.width
          height: parent.height - buttonRow.height - 43

          Row {
            anchors {
              fill: parent
              margins: 12
            }
            spacing: 14

            Column {
              width: 270
              height: parent.height
              spacing: 7

              Text {
                text: "Preview:"
                color: Win95Theme.text
                font.family: "Comic Code"
                font.pixelSize: 11
                renderType: Text.NativeRendering
              }

              Item {
                width: parent.width
                height: 205

                BevelRect {
                  id: previewMonitor
                  anchors {
                    top: parent.top
                    horizontalCenter: parent.horizontalCenter
                  }
                  width: 258
                  height: 176

                  Rectangle {
                    anchors {
                      fill: parent
                      margins: 12
                      bottomMargin: 18
                    }
                    color: Win95Theme.edgeDark

                    Rectangle {
                      id: previewDesktop
                      anchors {
                        fill: parent
                        margins: 3
                      }
                      color: Win95Theme.desktop
                      clip: true

                      Image {
                        anchors.fill: parent
                        source: Win95WallpaperState.selectedPath === ""
                          ? ""
                          : "file://" + Win95WallpaperState.selectedPath
                        fillMode: root.previewFillMode()
                        horizontalAlignment: Image.AlignHCenter
                        verticalAlignment: Image.AlignVCenter
                        asynchronous: true
                        cache: false
                        visible: status === Image.Ready
                      }
                    }
                  }
                }

                Rectangle {
                  anchors {
                    top: previewMonitor.bottom
                    horizontalCenter: parent.horizontalCenter
                  }
                  width: 76
                  height: 9
                  color: Win95Theme.face
                  border.width: 1
                  border.color: Win95Theme.edgeShadow
                }
              }

              Text {
                width: parent.width
                text: Win95WallpaperState.selectedPath === ""
                  ? "Solid desktop color"
                  : Win95WallpaperState.selectedPath.split("/").pop()
                color: Win95Theme.text
                font.family: "Comic Code"
                font.pixelSize: 11
                renderType: Text.NativeRendering
                elide: Text.ElideMiddle
                horizontalAlignment: Text.AlignHCenter
              }
            }

            Column {
              width: parent.width - 284
              height: parent.height
              spacing: 7

              Text {
                text: "Wallpaper:"
                color: Win95Theme.text
                font.family: "Comic Code"
                font.pixelSize: 11
                renderType: Text.NativeRendering
              }

              BevelRect {
                thin: true
                pressed: true
                width: parent.width
                height: parent.height - placementRow.height - utilityRow.height - 45

                Rectangle {
                  anchors {
                    fill: parent
                    margins: 2
                  }
                  color: Win95Theme.field

                  ListView {
                    id: wallpaperList
                    anchors.fill: parent
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: Win95WallpaperState.wallpapers
                    currentIndex: Win95WallpaperState.selectedIndex

                    delegate: Rectangle {
                      id: wallpaperRow
                      required property var modelData
                      required property int index

                      width: wallpaperList.width
                      height: 25
                      color: index === Win95WallpaperState.selectedIndex
                        ? Win95Theme.highlight
                        : Win95Theme.field

                      Text {
                        anchors {
                          left: parent.left
                          right: parent.right
                          leftMargin: 6
                          rightMargin: 6
                          verticalCenter: parent.verticalCenter
                        }
                        text: wallpaperRow.modelData.name
                        color: wallpaperRow.index === Win95WallpaperState.selectedIndex
                          ? Win95Theme.highlightText
                          : Win95Theme.fieldText
                        font.family: "Comic Code"
                        font.pixelSize: 11
                        renderType: Text.NativeRendering
                        elide: Text.ElideRight
                      }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: Win95WallpaperState.select(wallpaperRow.index)
                      }
                    }

                    ScrollBar.vertical: ScrollBar {
                      policy: ScrollBar.AsNeeded
                    }
                  }
                }
              }

              Row {
                id: placementRow
                width: parent.width
                height: 30
                spacing: 7

                Text {
                  width: 62
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Display:"
                  color: Win95Theme.text
                  font.family: "Comic Code"
                  font.pixelSize: 11
                  renderType: Text.NativeRendering
                }

                ComboBox {
                  width: parent.width - 69
                  height: parent.height
                  model: ["Fill", "Fit", "Center", "Tile", "Stretch"]
                  currentIndex: Math.max(0, root.placementKeys.indexOf(
                    Win95WallpaperState.selectedPlacement
                  ))
                  onActivated: index => {
                    Win95WallpaperState.selectedPlacement
                      = root.placementKeys[index];
                  }
                }
              }

              Row {
                id: utilityRow
                width: parent.width
                height: 28
                spacing: 7

                DialogButton {
                  width: (parent.width - 7) / 2
                  label: "Open Folder…"
                  onClicked: Win95WallpaperState.openFolder()
                }

                DialogButton {
                  width: (parent.width - 7) / 2
                  label: "Refresh"
                  onClicked: Win95WallpaperState.refreshWallpapers()
                }
              }
            }
          }
        }

        Row {
          id: buttonRow
          width: parent.width
          height: 28
          spacing: 8

          Item { width: parent.width - 280; height: 1 }

          DialogButton {
            label: "OK"
            defaultButton: true
            onClicked: Win95WallpaperState.accept()
          }

          DialogButton {
            label: "Cancel"
            onClicked: Win95WallpaperState.cancel()
          }

          DialogButton {
            label: "Apply"
            onClicked: Win95WallpaperState.applySelection()
          }
        }
      }

      Connections {
        target: Win95WallpaperState
        function onListSerialChanged(): void {
          if (wallpaperWindow.visible) {
            wallpaperList.positionViewAtIndex(
              Win95WallpaperState.selectedIndex,
              ListView.Contain
            );
          }
        }
      }
    }
  }
}
