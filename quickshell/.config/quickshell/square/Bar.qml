import Quickshell
import QtQuick
import "." as Square

// Flat swaybar-like bar, docked flush to the top edge.
// No per-module boxes, no hairline dividers, no borders.
Variants {
  model: Quickshell.screens

  PanelWindow {
    id: barWindow
    required property var modelData

    screen: modelData
    color: "transparent"

    anchors {
      top: true
      left: true
      right: true
    }

    implicitHeight: Theme.barHeight
    exclusiveZone: Theme.barHeight

    Rectangle {
      id: barBg
      anchors.fill: parent
      color: Theme.bg
      radius: 0

      // Notification arrival: glitch burst across the whole bar background,
      // painted behind the modules (first child = lowest in the stack).
      NotificationGlitch {
        id: notifGlitch
        anchors.fill: parent
      }

      Connections {
        target: Square.NotificationState
        function onNotified() { notifGlitch.play() }
      }

      // LEFT cluster: workspaces (all monitors, colour-coded)
      Workspaces {
        id: workspaces
        anchors {
          left: parent.left
          verticalCenter: parent.verticalCenter
        }
      }

      // CENTER: AI usage | tmux | vitals
      Row {
        id: centerStatus
        anchors.centerIn: parent
        spacing: Theme.gapLg

        AiUsageBlock {
          anchors.verticalCenter: parent.verticalCenter
          screenName: barWindow.modelData.name
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: 12
          color: Theme.border
        }

        Square.TmuxSessions {
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: 12
          color: Theme.border
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.padMd

          MetricsBlock {
            anchors.verticalCenter: parent.verticalCenter
          }

          NetSpeedBlock {
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }

      // RIGHT cluster: compact status groups
      Row {
        id: rightStatus
        anchors {
          right: parent.right
          top: parent.top
          bottom: parent.bottom
          rightMargin: Theme.padMd
        }
        spacing: Theme.padMd

        TrayBlock {
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: 12
          color: Theme.border
        }

        Square.NotificationBlock {
          anchors.verticalCenter: parent.verticalCenter
          screenName: barWindow.modelData.name
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: 12
          color: Theme.border
        }

        KeyboardBlock {
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: 12
          color: Theme.border
        }

        VolumeBlock {
          anchors.verticalCenter: parent.verticalCenter
          screenName: barWindow.modelData.name
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: 12
          color: Theme.border
        }

        Clock {
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
