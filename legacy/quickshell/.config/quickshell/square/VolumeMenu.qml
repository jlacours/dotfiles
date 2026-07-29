import QtQuick
import Quickshell
import Quickshell.Wayland

Scope {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: menuWindow
      required property var modelData
      readonly property bool activeScreen: AudioRateState.panelScreenName === modelData.name

      screen: modelData
      WlrLayershell.namespace: "quickshell-square-volume-menu-" + (modelData ? modelData.name : "default")
      WlrLayershell.layer: WlrLayer.Overlay
      color: "transparent"
      exclusiveZone: 0
      visible: AudioRateState.panelVisible && activeScreen
      implicitWidth: 250
      implicitHeight: menu.implicitHeight
      mask: Region { item: menu }

      anchors {
        top: true
        right: true
      }

      margins {
        top: Theme.barHeight + Theme.padSm
        right: 64
      }

      Rectangle {
        id: menu
        anchors.top: parent.top
        anchors.right: parent.right
        width: 250
        implicitHeight: content.implicitHeight + Theme.panelPadding * 2
        height: implicitHeight
        color: Theme.panelSurface
        border.width: Theme.hairline
        border.color: Theme.borderSubtle

        Column {
          id: content
          anchors.fill: parent
          anchors.margins: Theme.panelPadding
          spacing: Theme.panelGap

          Item {
            width: parent.width
            height: title.implicitHeight

            Text {
              id: title
              anchors.left: parent.left
              text: "AUDIO RATE"
              color: Theme.textMuted
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSm
              font.bold: true
            }

            Text {
              anchors.right: parent.right
              text: AudioRateState.ok
                ? AudioRateState.formatRate(AudioRateState.graphRate) + " KHZ"
                : "N/A"
              color: AudioRateState.ok ? Theme.accent : Theme.critical
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontMd
              font.bold: true
            }
          }

          Text {
            width: parent.width
            text: {
              const sink = VolumeState.sink
              if (!sink) return "NO AUDIO OUTPUT"
              const props = sink.properties || ({})
              return String(props["node.nick"] || props["node.description"] || "AUDIO OUTPUT").toUpperCase()
            }
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSm
            elide: Text.ElideRight
          }

          Rectangle {
            width: parent.width
            height: Theme.hairline
            color: Theme.borderSubtle
          }

          Row {
            width: parent.width
            spacing: Theme.padSm

            Repeater {
              model: AudioRateState.rates

              Rectangle {
                id: rateButton
                required property int modelData
                readonly property bool selected: AudioRateState.forcedRate === modelData
                width: (content.width - Theme.padSm * 4) / 5
                height: 26
                color: selected ? Theme.accent : (rateArea.containsMouse ? Theme.borderActive : Theme.bg)
                border.width: Theme.hairline
                border.color: selected ? Theme.accent : Theme.border

                Text {
                  anchors.centerIn: parent
                  text: AudioRateState.formatRate(rateButton.modelData)
                  color: rateButton.selected ? Theme.bg : Theme.text
                  font.family: Theme.fontFamily
                  font.pixelSize: Theme.fontSm
                  font.bold: true
                }

                MouseArea {
                  id: rateArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: AudioRateState.selectRate(rateButton.modelData)
                }
              }
            }
          }

          Text {
            width: parent.width
            text: AudioRateState.forcedRate === 0
              ? "AUTO · PIPEWIRE SELECTS THE GRAPH RATE"
              : "MANUAL · LIVE OUTPUT MAY RESAMPLE"
            color: Theme.textDim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSm
            elide: Text.ElideRight
          }
        }
      }
    }
  }
}
