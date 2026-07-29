import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "." as Keybinds
import "../wallust.js" as Wallust

Scope {
  id: root

  readonly property color bgBase: Wallust.bg
  readonly property color surfaceBase: Wallust.surfaceElevated
  readonly property color borderBase: Wallust.border
  readonly property color panelSurface: Qt.rgba(bgBase.r, bgBase.g, bgBase.b, 0.90)
  readonly property color cardSurface: Qt.rgba(surfaceBase.r, surfaceBase.g, surfaceBase.b, 0.60)
  readonly property color borderSubtle: Qt.rgba(borderBase.r, borderBase.g, borderBase.b, 0.48)

  component LegendChip: Rectangle {
    required property string label
    required property color chipColor

    width: legendLabel.implicitWidth + 28
    height: 28
    color: chipColor
    border.width: 1
    border.color: root.panelSurface

    Text {
      id: legendLabel
      anchors.centerIn: parent
      text: parent.label
      color: Wallust.base00
      font.family: "Comic Code"
      font.pixelSize: 10
      font.bold: true
    }
  }

  component MouseBox: Rectangle {
    required property string title
    required property string keyId

    readonly property var bindData: {
      const binds = Keybinds.KeybindState.mouseBinds()
      for (let i = 0; i < binds.length; i++) {
        if (binds[i].normalizedKey === keyId) return binds[i]
      }
      return null
    }

    width: parent ? Math.floor((parent.width - 12) / 3) : 120
    height: 86
    color: bindData ? Wallust.base0F : root.cardSurface
    border.width: 1
    border.color: bindData ? Wallust.base0F : root.borderSubtle

    Text {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: 7
      anchors.topMargin: 7
      width: parent.width - 14
      visible: !!parent.bindData
      text: parent.bindData ? parent.bindData.desc : ""
      color: Wallust.base00
      font.family: "Comic Code"
      font.pixelSize: 7
      wrapMode: Text.Wrap
      maximumLineCount: 3
      lineHeight: 0.9
      elide: Text.ElideRight
      clip: true
    }

    Text {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.leftMargin: 8
      anchors.bottomMargin: 6
      width: parent.width - 16
      text: parent.title.replace("BUTTON", "BUTTON\n")
      color: parent.bindData ? Wallust.base00 : Wallust.text
      font.family: "Comic Code"
      font.pixelSize: 8
      font.bold: true
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: overlayWindow
      required property var modelData

      screen: modelData
      color: "transparent"
      exclusiveZone: 0
      WlrLayershell.keyboardFocus: (Keybinds.KeybindState.visible && Keybinds.KeybindState.screenName === modelData.name)
        ? WlrKeyboardFocus.Exclusive
        : WlrKeyboardFocus.None
      visible: (Keybinds.KeybindState.visible && Keybinds.KeybindState.screenName === modelData.name) || overlayAnim.running

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: Keybinds.KeybindState.visible && Keybinds.KeybindState.screenName === modelData.name
        onActivated: Keybinds.KeybindState.hide()
      }

      Rectangle {
        anchors.fill: parent
        color: root.bgBase
        opacity: Keybinds.KeybindState.visible && Keybinds.KeybindState.screenName === modelData.name ? 0.26 : 0

        Behavior on opacity {
          NumberAnimation {
            duration: 150
            easing.type: Easing.OutQuad
          }
        }
      }

      MouseArea {
        anchors.fill: parent
        visible: Keybinds.KeybindState.visible && Keybinds.KeybindState.screenName === modelData.name
        onClicked: Keybinds.KeybindState.hide()
      }

      Rectangle {
        id: panel
        readonly property bool activeScreen: Keybinds.KeybindState.screenName === modelData.name
        readonly property bool overlayVisible: Keybinds.KeybindState.visible && activeScreen
        readonly property int panelWidth: Math.min(modelData.width - 80, 1520)
        readonly property int panelHeight: Math.min(modelData.height - 80, 900)

        width: panelWidth
        height: panelHeight
        anchors.centerIn: parent
        color: root.panelSurface
        border.width: 1
        border.color: root.borderSubtle
        opacity: overlayVisible ? 1 : 0

        transform: Translate {
          y: panel.overlayVisible ? 0 : 18

          Behavior on y {
            NumberAnimation {
              id: overlayAnim
              duration: 170
              easing.type: Easing.OutQuad
            }
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: 170
            easing.type: Easing.OutQuad
          }
        }

        Item {
          id: panelContent
          anchors.fill: parent
          anchors.margins: 22
          focus: true
          Keys.onEscapePressed: Keybinds.KeybindState.hide()

          Component.onCompleted: forceActiveFocus()

          Connections {
            target: Keybinds.KeybindState

            function onVisibleChanged() {
              if (Keybinds.KeybindState.visible && panel.activeScreen) {
                panelContent.forceActiveFocus()
              }
            }
          }

          Column {
            anchors.fill: parent
            spacing: 16

            Item {
              width: parent.width
              height: 56

              Text {
                anchors.left: parent.left
                anchors.top: parent.top
                text: "HYPRLAND KEYBINDS"
                color: Wallust.text
                font.family: "Comic Code"
                font.pixelSize: 16
                font.bold: true
              }

              Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.topMargin: 26
                text: "MODIFIERS: " + (Keybinds.KeybindState.selectedModifierMode === "PLAIN"
                  ? "NONE"
                  : Keybinds.KeybindState.selectedModifierMode.toLowerCase().split("+").join(", "))
                color: Wallust.textMuted
                font.family: "Comic Code"
                font.pixelSize: 11
              }

              Text {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: 320
                anchors.topMargin: 26
                text: "SUBMAP: " + Keybinds.KeybindState.selectedSubmap.toUpperCase()
                color: Wallust.textDim
                font.family: "Comic Code"
                font.pixelSize: 11
                font.bold: true
              }

              Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                width: closeText.implicitWidth + 18
                height: 28
                color: "transparent"
                border.width: 1
                border.color: root.borderSubtle

                Text {
                  id: closeText
                  anchors.centerIn: parent
                  text: "ESC"
                  color: Wallust.text
                  font.family: "Comic Code"
                  font.pixelSize: 10
                  font.bold: true
                }

                MouseArea {
                  anchors.fill: parent
                  onClicked: Keybinds.KeybindState.hide()
                }
              }
            }

            Flickable {
              width: parent.width
              height: 34
              contentWidth: modeRow.implicitWidth
              clip: true

              Row {
                id: modeRow
                spacing: 8

                Repeater {
                  model: Keybinds.KeybindState.modifierModes

                  delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: Keybinds.KeybindState.selectedModifierMode === modelData

                    width: label.implicitWidth + 20
                    height: 30
                    color: selected ? Wallust.accentPrimary : root.cardSurface
                    border.width: 1
                    border.color: selected ? Wallust.accentPrimary : root.borderSubtle

                    Text {
                      id: label
                      anchors.centerIn: parent
                      text: modelData
                      color: parent.selected ? Wallust.base00 : Wallust.text
                      font.family: "Comic Code"
                      font.pixelSize: 10
                      font.bold: true
                    }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: Keybinds.KeybindState.setModifierMode(modelData)
                    }
                  }
                }
              }
            }

            Flickable {
              width: parent.width
              height: 30
              contentWidth: submapRow.implicitWidth
              clip: true

              Row {
                id: submapRow
                spacing: 8

                Repeater {
                  model: Keybinds.KeybindState.submaps

                  delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: Keybinds.KeybindState.selectedSubmap === modelData

                    width: label.implicitWidth + 18
                    height: 26
                    color: selected ? root.cardSurface : "transparent"
                    border.width: 1
                    border.color: selected ? Wallust.accentPrimary : root.borderSubtle

                    Text {
                      id: label
                      anchors.centerIn: parent
                      text: modelData.toUpperCase()
                      color: selected ? Wallust.accentPrimary : Wallust.textMuted
                      font.family: "Comic Code"
                      font.pixelSize: 9
                      font.bold: true
                    }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: Keybinds.KeybindState.setSubmap(modelData)
                    }
                  }
                }
              }
            }

            Item {
              width: parent.width
              height: parent.height - y

              Item {
                id: keyboardStage
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width - sideStage.width - 18

                Rectangle {
                  anchors.fill: parent
                  color: root.cardSurface
                  border.width: 1
                  border.color: root.borderSubtle
                }

                Text {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.leftMargin: 14
                  anchors.topMargin: 12
                  text: "KEYBOARD"
                  color: Wallust.textMuted
                  font.family: "Comic Code"
                  font.pixelSize: 10
                  font.bold: true
                }

                Item {
                  id: keyboardArea
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.bottom: legendRow.top
                  anchors.margins: 12
                  anchors.topMargin: 34
                  anchors.bottomMargin: 14

                  Keybinds.KeyboardView {
                    id: keyboardView
                    readonly property real scaleFactor: Math.min(
                      keyboardArea.width / contentWidth,
                      keyboardArea.height / contentHeight
                    )
                    anchors.left: parent.left
                    anchors.top: parent.top
                    scale: scaleFactor
                    transformOrigin: Item.TopLeft
                  }
                }

                Row {
                  id: legendRow
                  anchors.left: parent.left
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: 12
                  anchors.bottomMargin: 12
                  spacing: 8

                  LegendChip { label: "MODIFIERS"; chipColor: Wallust.base08 }
                  LegendChip { label: "LAYOUT"; chipColor: Wallust.base0C }
                  LegendChip { label: "WORKSPACE"; chipColor: Wallust.base0A }
                  LegendChip { label: "WINDOW"; chipColor: Wallust.base09 }
                  LegendChip { label: "LAUNCH"; chipColor: Wallust.base0E }
                  LegendChip { label: "SYSTEM"; chipColor: Wallust.base0B }
                }
              }

              Item {
                id: sideStage
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 180

                ColumnLayout {
                  anchors.fill: parent
                  spacing: 16

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 160
                    color: root.cardSurface
                    border.width: 1
                    border.color: root.borderSubtle

                    Column {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 8
                      clip: true

                      Text {
                        text: "ACTIVE KEYS"
                        color: Wallust.textMuted
                        font.family: "Comic Code"
                        font.pixelSize: 10
                        font.bold: true
                      }

                      Repeater {
                        model: Keybinds.KeybindState.activeBinds.slice(0, 8)

                        delegate: Text {
                          required property var modelData

                          width: parent.width
                          text: modelData.combo + "  " + modelData.desc
                          color: Wallust.text
                          font.family: "Comic Code"
                          font.pixelSize: 9
                          wrapMode: Text.WordWrap
                          maximumLineCount: 2
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    color: root.cardSurface
                    border.width: 1
                    border.color: root.borderSubtle

                    Column {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 12
                      clip: true

                      Text {
                        text: "MOUSE"
                        color: Wallust.textMuted
                        font.family: "Comic Code"
                        font.pixelSize: 10
                        font.bold: true
                      }

                      Row {
                        width: parent.width
                        spacing: 6

                        MouseBox { title: "BUTTON1"; keyId: "MOUSE_LEFT" }
                        MouseBox { title: "BUTTON2"; keyId: "MOUSE_MIDDLE" }
                        MouseBox { title: "BUTTON3"; keyId: "MOUSE_RIGHT" }
                      }
                    }
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    color: root.cardSurface
                    border.width: 1
                    border.color: root.borderSubtle
                    visible: Keybinds.KeybindState.unplacedBinds().length > 0

                    Column {
                      anchors.fill: parent
                      anchors.margins: 14
                      spacing: 8
                      clip: true

                      Text {
                        text: "UNPLACED"
                        color: Wallust.textMuted
                        font.family: "Comic Code"
                        font.pixelSize: 10
                        font.bold: true
                      }

                      Repeater {
                        model: Keybinds.KeybindState.unplacedBinds().slice(0, 10)

                        delegate: Text {
                          required property var modelData

                          width: parent.width
                          text: modelData.combo + "  " + modelData.desc
                          color: Wallust.text
                          font.family: "Comic Code"
                          font.pixelSize: 9
                          wrapMode: Text.WordWrap
                          maximumLineCount: 2
                          elide: Text.ElideRight
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  IpcHandler {
    target: "keybinds"

    function toggle(monitorName: string): void {
      Keybinds.KeybindState.toggle(monitorName)
    }

    function hide(): void {
      Keybinds.KeybindState.hide()
    }
  }
}
