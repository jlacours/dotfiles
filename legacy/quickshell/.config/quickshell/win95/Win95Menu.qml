import QtQuick
import QtQuick.Controls
import Quickshell

// Exact-size native popup for launchers and dmenu-backed scripts. Unlike the
// square profile's centered overlay, this never creates a fullscreen surface.
PopupWindow {
  id: root

  required property var barWindow
  required property string outputName

  readonly property int menuWidth: Math.min(640, Math.max(460, barWindow.width - 32))
  readonly property int menuHeight: Math.min(430, Math.max(300, barWindow.screen.height - 96))
  readonly property bool requestedVisible: Win95MenuState.visible
    && Win95MenuState.mode !== "apps"
    && Win95MenuState.screenName === outputName

  anchor.window: barWindow
  anchor.rect.x: Math.max(0, Math.floor((barWindow.width - menuWidth) / 2))
  anchor.rect.y: 0
  anchor.rect.width: menuWidth
  anchor.rect.height: 1
  anchor.edges: Edges.Top | Edges.Left
  anchor.gravity: Edges.Top | Edges.Right

  color: "transparent"
  grabFocus: true
  visible: requestedVisible
  implicitWidth: menuWidth
  implicitHeight: menuHeight

  onVisibleChanged: {
    if (visible) {
      filterInput.text = Win95MenuState.filterText;
      resetSelection(Win95MenuState.initialSelectedRow);
      focusTimer.restart();
    } else if (requestedVisible) {
      Win95MenuState.cancelCurrent();
    }
  }

  Shortcut {
    sequence: "Escape"
    enabled: root.visible
    onActivated: Win95MenuState.cancelCurrent()
  }

  Shortcut {
    sequence: "Down"
    enabled: root.visible && menuList.count > 0
    onActivated: moveSelection(1)
  }

  Shortcut {
    sequence: "Up"
    enabled: root.visible && menuList.count > 0
    onActivated: moveSelection(-1)
  }

  Shortcut {
    sequence: "Return"
    enabled: root.visible
    onActivated: Win95MenuState.activateCurrent(menuList.currentIndex)
  }

  Timer {
    id: focusTimer
    interval: 40
    onTriggered: filterInput.forceActiveFocus()
  }

  // Same belt-and-suspenders guard as the Start menu: a compositor regression
  // may be annoying for 15 seconds, but it does not get permanent custody of
  // the keyboard.
  Timer {
    interval: 15000
    running: root.visible
    onTriggered: Win95MenuState.cancelCurrent()
  }

  BevelRect {
    anchors.fill: parent

    Column {
      anchors {
        fill: parent
        margins: 5
      }
      spacing: 5

      Rectangle {
        width: parent.width
        height: 28
        color: Win95Theme.highlight

        Text {
          anchors {
            left: parent.left
            leftMargin: 7
            verticalCenter: parent.verticalCenter
          }
          text: Win95MenuState.promptText
          color: Win95Theme.highlightText
          font.family: "Comic Code"
          font.pixelSize: 13
          font.bold: true
          renderType: Text.NativeRendering
        }

        Text {
          anchors {
            right: parent.right
            rightMargin: 7
            verticalCenter: parent.verticalCenter
          }
          text: menuList.count + " item" + (menuList.count === 1 ? "" : "s")
          color: Win95Theme.highlightText
          font.family: "Comic Code"
          font.pixelSize: 11
          renderType: Text.NativeRendering
        }
      }

      BevelRect {
        thin: true
        pressed: true
        width: parent.width
        height: 34

        Rectangle {
          anchors {
            fill: parent
            margins: 2
          }
          color: Win95Theme.field

          TextInput {
            id: filterInput
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
            clip: true
            selectByMouse: true
            onTextChanged: {
              Win95MenuState.setFilterText(text);
              root.resetSelection(0);
            }
          }

          Text {
            anchors {
              left: parent.left
              leftMargin: 5
              verticalCenter: parent.verticalCenter
            }
            visible: filterInput.text === "" && !filterInput.activeFocus
            text: "Type to filter"
            color: Win95Theme.mutedText
            font.family: "Comic Code"
            font.pixelSize: 12
          }
        }
      }

      BevelRect {
        thin: true
        pressed: true
        width: parent.width
        height: parent.height - y

        Rectangle {
          anchors {
            fill: parent
            margins: 2
          }
          color: Win95Theme.field

          ListView {
            id: menuList
            anchors.fill: parent
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: Win95MenuState.filteredItems
            currentIndex: count > 0 ? 0 : -1

            delegate: Rectangle {
              id: row
              required property var modelData
              required property int index

              width: menuList.width
              height: modelData.sub ? 40 : 30
              color: ListView.isCurrentItem ? Win95Theme.highlight : Win95Theme.field

              Column {
                anchors {
                  left: parent.left
                  right: parent.right
                  leftMargin: 7
                  rightMargin: 7
                  verticalCenter: parent.verticalCenter
                }
                spacing: 1

                Text {
                  width: parent.width
                  text: row.modelData.text
                  color: row.ListView.isCurrentItem ? Win95Theme.highlightText : Win95Theme.fieldText
                  font.family: "Comic Code"
                  font.pixelSize: 12
                  renderType: Text.NativeRendering
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  visible: text !== ""
                  text: row.modelData.sub || ""
                  color: row.ListView.isCurrentItem ? Win95Theme.highlightText : Win95Theme.mutedText
                  font.family: "Comic Code"
                  font.pixelSize: 10
                  renderType: Text.NativeRendering
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: menuList.currentIndex = row.index
                onClicked: Win95MenuState.activateCurrent(row.index)
              }
            }

            ScrollBar.vertical: ScrollBar {
              policy: ScrollBar.AsNeeded
            }
          }

          Text {
            anchors.centerIn: parent
            visible: menuList.count === 0
            text: "No matches"
            color: Win95Theme.mutedText
            font.family: "Comic Code"
            font.pixelSize: 12
          }
        }
      }
    }
  }

  Connections {
    target: Win95MenuState
    function onResetSelectionSerialChanged(): void {
      if (root.visible)
        root.resetSelection(Win95MenuState.initialSelectedRow);
    }
  }

  function resetSelection(preferredRow): void {
    if (menuList.count === 0) {
      menuList.currentIndex = -1;
      return;
    }
    menuList.currentIndex = Math.max(0, Math.min(menuList.count - 1, preferredRow || 0));
    menuList.positionViewAtIndex(menuList.currentIndex, ListView.Beginning);
  }

  function moveSelection(delta): void {
    if (menuList.count === 0)
      return;
    const current = menuList.currentIndex < 0 ? 0 : menuList.currentIndex;
    menuList.currentIndex = Math.max(0, Math.min(menuList.count - 1, current + delta));
    menuList.positionViewAtIndex(menuList.currentIndex, ListView.Contain);
  }
}
