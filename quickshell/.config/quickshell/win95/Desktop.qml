import Quickshell
import Quickshell.Wayland
import QtQuick

// Opaque desktop surface behind every window. Left-drag draws the gloriously
// useless Win95 selection marquee; right-click asks labwc for its real menu.
Scope {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: desktopWindow
      required property var modelData

      property bool selecting: false
      property real selectionStartX: 0
      property real selectionStartY: 0
      property real selectionEndX: 0
      property real selectionEndY: 0

      screen: modelData
      color: Win95Theme.desktop
      exclusionMode: ExclusionMode.Ignore

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      WlrLayershell.namespace: "juju95-desktop"

      Image {
        anchors.fill: parent
        clip: true
        source: Win95WallpaperState.wallpaperPath === ""
          ? ""
          : "file://" + Win95WallpaperState.wallpaperPath
        fillMode: {
          switch (Win95WallpaperState.placement) {
          case "fit": return Image.PreserveAspectFit;
          case "center": return Image.Pad;
          case "tile": return Image.Tile;
          case "stretch": return Image.Stretch;
          default: return Image.PreserveAspectCrop;
          }
        }
        horizontalAlignment: Image.AlignHCenter
        verticalAlignment: Image.AlignVCenter
        asynchronous: true
        cache: false
        visible: status === Image.Ready
      }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true

        onPressed: mouse => {
          Win95MenuState.requestStartClose();

          if (mouse.button === Qt.RightButton) {
            desktopWindow.selecting = false;
            Quickshell.execDetached([
              "wtype", "-M", "logo", "-M", "shift", "-k", "F12"
            ]);
            return;
          }

          desktopWindow.selectionStartX = mouse.x;
          desktopWindow.selectionStartY = mouse.y;
          desktopWindow.selectionEndX = mouse.x;
          desktopWindow.selectionEndY = mouse.y;
          desktopWindow.selecting = true;
          selectionBox.requestPaint();
        }

        onPositionChanged: mouse => {
          if (!desktopWindow.selecting
              || !(mouse.buttons & Qt.LeftButton))
            return;

          desktopWindow.selectionEndX = mouse.x;
          desktopWindow.selectionEndY = mouse.y;
          selectionBox.requestPaint();
        }

        onReleased: mouse => {
          if (mouse.button === Qt.LeftButton)
            desktopWindow.selecting = false;
        }

        onCanceled: desktopWindow.selecting = false
      }

      Canvas {
        id: selectionBox
        x: Math.floor(Math.min(
          desktopWindow.selectionStartX,
          desktopWindow.selectionEndX
        ))
        y: Math.floor(Math.min(
          desktopWindow.selectionStartY,
          desktopWindow.selectionEndY
        ))
        width: Math.max(1, Math.ceil(Math.abs(
          desktopWindow.selectionEndX - desktopWindow.selectionStartX
        )))
        height: Math.max(1, Math.ceil(Math.abs(
          desktopWindow.selectionEndY - desktopWindow.selectionStartY
        )))
        visible: desktopWindow.selecting && width > 2 && height > 2

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
          const context = getContext("2d");
          context.reset();
          context.lineWidth = 1;
          context.strokeStyle = "#000000";
          context.strokeRect(0.5, 0.5, width - 1, height - 1);
          context.setLineDash([2, 2]);
          context.strokeStyle = "#ffffff";
          context.strokeRect(0.5, 0.5, width - 1, height - 1);
        }
      }
    }
  }
}
