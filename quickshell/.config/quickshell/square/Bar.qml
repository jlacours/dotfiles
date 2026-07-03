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

      // LEFT cluster: workspaces, then the center-module toggle switches
      // (AI usage | tmux | vitals glyphs). Each glyph is dim while its module
      // is hidden -- left-click flips visibility via CenterModulesState.
      Workspaces {
        id: workspaces
        anchors {
          left: parent.left
          verticalCenter: parent.verticalCenter
        }
      }

      Rectangle {
        id: leftTogglesDivider
        anchors {
          left: workspaces.right
          leftMargin: Theme.padMd
          verticalCenter: parent.verticalCenter
        }
        width: Theme.hairline
        height: Theme.dividerHeight
        color: Theme.borderSubtle
      }

      Square.CenterToggleBlock {
        anchors {
          left: leftTogglesDivider.right
          leftMargin: Theme.padMd
          verticalCenter: parent.verticalCenter
        }
      }

      // CENTER: AI usage | tmux | vitals
      // Each unit is independently toggleable (toggles now live in the left
      // cluster, via CenterToggleBlock / CenterModulesState); dividers hide
      // themselves whenever an adjacent unit is hidden so no orphan hairlines
      // remain.
      Row {
        id: centerStatus
        anchors.centerIn: parent
        spacing: Theme.gapLg
        visible: !CenterModulesState.news

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

      // News ticker: replaces the status group when toggled on.
      RssBlock {
        anchors.centerIn: parent
        visible: CenterModulesState.news
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
