import QtQuick
import Quickshell

// A real floating window, like Windows 95 Find—not a taskbar-attached command
// palette. Labwc supplies the matching server-side titlebar and close button.
Scope {
  Variants {
    model: Quickshell.screens

    FloatingWindow {
      id: findWindow
      required property var modelData

      readonly property bool requestedVisible: Win95MenuState.visible
        && Win95MenuState.mode === "apps"
        && Win95MenuState.screenName === modelData.name

      screen: modelData
      title: "Find: Applications"
      color: Win95Theme.face
      visible: requestedVisible
      implicitWidth: Math.min(620, modelData.width - 48)
      implicitHeight: Math.min(470, modelData.height - 80)

      onVisibleChanged: {
        if (visible) {
          searchInput.text = Win95MenuState.filterText;
          results.currentIndex = results.count > 0 ? 0 : -1;
          focusTimer.restart();
        } else if (requestedVisible) {
          Win95MenuState.cancelCurrent();
        }
      }

      Shortcut {
        sequence: "Escape"
        enabled: findWindow.visible
        onActivated: Win95MenuState.cancelCurrent()
      }

      Shortcut {
        sequence: "Down"
        enabled: findWindow.visible && results.count > 0
        onActivated: moveSelection(1)
      }

      Shortcut {
        sequence: "Up"
        enabled: findWindow.visible && results.count > 0
        onActivated: moveSelection(-1)
      }

      Shortcut {
        sequence: "Return"
        enabled: findWindow.visible && results.currentIndex >= 0
        onActivated: Win95MenuState.activateCurrent(results.currentIndex)
      }

      Timer {
        id: focusTimer
        interval: 50
        onTriggered: searchInput.forceActiveFocus()
      }

      Column {
        anchors {
          fill: parent
          margins: 10
        }
        spacing: 8

        Row {
          width: parent.width
          height: 32
          spacing: 8

          Text {
            width: 58
            anchors.verticalCenter: parent.verticalCenter
            text: "Named:"
            color: Win95Theme.text
            font.family: "Comic Code"
            font.pixelSize: 12
            renderType: Text.NativeRendering
          }

          BevelRect {
            thin: true
            pressed: true
            width: parent.width - 66
            height: parent.height

            Rectangle {
              anchors {
                fill: parent
                margins: 2
              }
              color: Win95Theme.field

              TextInput {
                id: searchInput
                anchors {
                  fill: parent
                  margins: 5
                }
                color: Win95Theme.fieldText
                selectionColor: Win95Theme.highlight
                selectedTextColor: Win95Theme.highlightText
                font.family: "Comic Code"
                font.pixelSize: 12
                verticalAlignment: Text.AlignVCenter
                selectByMouse: true
                clip: true
                onTextChanged: {
                  Win95MenuState.setFilterText(text);
                  results.currentIndex = results.count > 0 ? 0 : -1;
                }
              }
            }
          }
        }

        Text {
          text: "Look in: Installed applications"
          color: Win95Theme.text
          font.family: "Comic Code"
          font.pixelSize: 11
          renderType: Text.NativeRendering
        }

        BevelRect {
          thin: true
          pressed: true
          width: parent.width
          height: parent.height - y - buttonRow.height - parent.spacing

          Rectangle {
            anchors {
              fill: parent
              margins: 2
            }
            color: Win95Theme.field

            Column {
              anchors.fill: parent
              spacing: 0

              Rectangle {
                width: parent.width
                height: 25
                color: Win95Theme.face
                border.width: 1
                border.color: Win95Theme.edgeShadow

                Row {
                  anchors.fill: parent

                  Text {
                    width: parent.parent.width * 0.52
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 6
                    text: "Name"
                    color: Win95Theme.text
                    font.family: "Comic Code"
                    font.pixelSize: 11
                    font.bold: true
                  }
                  Rectangle {
                    width: 1
                    height: parent.height
                    color: Win95Theme.edgeShadow
                  }
                  Text {
                    width: parent.parent.width * 0.48 - 1
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: 6
                    text: "Description"
                    color: Win95Theme.text
                    font.family: "Comic Code"
                    font.pixelSize: 11
                    font.bold: true
                  }
                }
              }

              ListView {
                id: results
                width: parent.width
                height: parent.height - 25
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: Win95MenuState.filteredItems
                currentIndex: count > 0 ? 0 : -1

                delegate: Rectangle {
                  id: resultRow
                  required property var modelData
                  required property int index

                  width: results.width
                  height: 26
                  color: ListView.isCurrentItem ? Win95Theme.highlight : Win95Theme.field

                  Row {
                    anchors.fill: parent

                    Text {
                      width: parent.width * 0.52
                      anchors.verticalCenter: parent.verticalCenter
                      leftPadding: 6
                      text: resultRow.modelData.text
                      color: resultRow.ListView.isCurrentItem
                        ? Win95Theme.highlightText : Win95Theme.fieldText
                      font.family: "Comic Code"
                      font.pixelSize: 11
                      elide: Text.ElideRight
                    }
                    Text {
                      width: parent.width * 0.48
                      anchors.verticalCenter: parent.verticalCenter
                      leftPadding: 6
                      text: resultRow.modelData.sub || ""
                      color: resultRow.ListView.isCurrentItem
                        ? Win95Theme.highlightText : Win95Theme.mutedText
                      font.family: "Comic Code"
                      font.pixelSize: 10
                      elide: Text.ElideRight
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: results.currentIndex = resultRow.index
                    onClicked: results.currentIndex = resultRow.index
                    onDoubleClicked: Win95MenuState.activateCurrent(resultRow.index)
                  }
                }
              }
            }

            Text {
              anchors.centerIn: parent
              visible: results.count === 0
              text: "No applications found."
              color: Win95Theme.mutedText
              font.family: "Comic Code"
              font.pixelSize: 11
            }
          }
        }

        Row {
          id: buttonRow
          width: parent.width
          height: 30
          spacing: 8

          Text {
            width: parent.width - 208
            anchors.verticalCenter: parent.verticalCenter
            text: results.count + " item" + (results.count === 1 ? "" : "s") + " found"
            color: Win95Theme.text
            font.family: "Comic Code"
            font.pixelSize: 11
          }

          BevelRect {
            width: 96
            height: parent.height

            Text {
              anchors.centerIn: parent
              text: "Open"
              color: Win95Theme.text
              font.family: "Comic Code"
              font.pixelSize: 11
            }
            MouseArea {
              anchors.fill: parent
              onClicked: Win95MenuState.activateCurrent(results.currentIndex)
            }
          }

          BevelRect {
            width: 96
            height: parent.height

            Text {
              anchors.centerIn: parent
              text: "Close"
              color: Win95Theme.text
              font.family: "Comic Code"
              font.pixelSize: 11
            }
            MouseArea {
              anchors.fill: parent
              onClicked: Win95MenuState.cancelCurrent()
            }
          }
        }
      }

      function moveSelection(delta): void {
        if (results.count === 0)
          return;
        const current = results.currentIndex < 0 ? 0 : results.currentIndex;
        results.currentIndex = Math.max(0, Math.min(results.count - 1, current + delta));
        results.positionViewAtIndex(results.currentIndex, ListView.Contain);
      }
    }
  }
}
