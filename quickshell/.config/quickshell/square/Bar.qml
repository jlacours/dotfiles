import Quickshell
import QtQuick
import "." as Square

// Flat swaybar-like bar, docked flush to the top edge.
// No per-module boxes; short, subtle hairlines separate logical groups.
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
      color: Theme.barSurface
      radius: 0

      // LEFT cluster: workspaces (all monitors, colour-coded)
      Workspaces {
        id: workspaces
        anchors {
          left: parent.left
          verticalCenter: parent.verticalCenter
        }
      }

      // CENTER: AI usage | tmux | vitals
      // Each unit is independently toggleable from the tray (see
      // CenterToggleBlock / CenterModulesState); dividers hide themselves
      // whenever an adjacent unit is hidden so no orphan hairlines remain.
      Row {
        id: centerStatus
        anchors.centerIn: parent
        spacing: Theme.gapLg

        AiUsageBlock {
          anchors.verticalCenter: parent.verticalCenter
          screenName: barWindow.modelData.name
          visible: CenterModulesState.aiUsage
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: Theme.dividerHeight
          color: Theme.borderSubtle
          visible: CenterModulesState.aiUsage && CenterModulesState.tmux
        }

        Square.TmuxSessions {
          anchors.verticalCenter: parent.verticalCenter
          visible: CenterModulesState.tmux
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: Theme.dividerHeight
          color: Theme.borderSubtle
          visible: CenterModulesState.tmux && CenterModulesState.vitals
        }

        Row {
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.padMd
          visible: CenterModulesState.vitals

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
          rightMargin: Theme.padLg
        }
        spacing: Theme.panelGap

        TrayBlock {
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: Theme.dividerHeight
          color: Theme.borderSubtle
        }

        // Center-module visibility toggles (their own section, right of tray).
        Square.CenterToggleBlock {
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: Theme.dividerHeight
          color: Theme.borderSubtle
        }

        Square.NotificationBlock {
          anchors.verticalCenter: parent.verticalCenter
          screenName: barWindow.modelData.name
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: Theme.dividerHeight
          color: Theme.borderSubtle
        }

        KeyboardBlock {
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: Theme.dividerHeight
          color: Theme.borderSubtle
        }

        VolumeBlock {
          anchors.verticalCenter: parent.verticalCenter
          screenName: barWindow.modelData.name
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: Theme.dividerHeight
          color: Theme.borderSubtle
        }

        // SearXNG + gluetun VPN sidecar: left-click toggles, right-click logs.
        SearxngVpnBlock {
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: Theme.dividerHeight
          color: Theme.borderSubtle
        }

        ExpressVpnBlock {
          anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.hairline
          height: Theme.dividerHeight
          color: Theme.borderSubtle
        }

        Clock {
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
