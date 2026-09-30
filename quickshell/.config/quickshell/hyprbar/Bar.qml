import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import QtQuick 6.0
import QtQuick.Layouts 6.0

PanelWindow {
    id: bar

    readonly property color background: palette.background
    readonly property color surface: palette.surface
    readonly property color surfaceHover: palette.surfaceHover
    readonly property color border: palette.border
    readonly property color foreground: palette.foreground
    readonly property color muted: palette.muted
    readonly property color accent: palette.accent
    readonly property var hyprMonitor: Hyprland.monitorFor(screen)
    readonly property string monitorName: hyprMonitor?.name || screen.name
    readonly property bool isTopMonitor: monitorName === "DP-1"

    WallustPalette {
        id: palette
    }

    WorkspaceNames {
        id: workspaceNames
    }

    color: "transparent"
    implicitHeight: 22
    exclusiveZone: 22

    anchors {
        top: !bar.isTopMonitor
        bottom: bar.isTopMonitor
        left: true
        right: true
    }

    Rectangle {
        anchors.fill: parent
        color: bar.background

        RowLayout {
            id: leftCluster
            anchors {
                left: parent.left
                leftMargin: 7
                verticalCenter: parent.verticalCenter
            }
            spacing: 2

            Repeater {
                model: 10

                delegate: Rectangle {
                    id: workspaceButton

                    required property int index
                    readonly property int workspaceId: index + 1
                    readonly property bool active: bar.hyprMonitor?.activeWorkspace?.id === workspaceId
                    readonly property var workspaceData: {
                        const workspaces = Hyprland.workspaces.values

                        for (let i = 0; i < workspaces.length; i++) {
                            if (workspaces[i].id === workspaceId)
                                return workspaces[i]
                        }

                        return null
                    }
                    readonly property string workspaceName: workspaceNames.nameFor(workspaceId)
                    readonly property bool occupied: workspaceData?.toplevels.values.length > 0

                    implicitWidth: Math.max(23, Math.min(115, workspaceLabel.implicitWidth + 14))
                    implicitHeight: 22
                    radius: 0
                    color: active ? bar.accent : workspaceMouse.containsMouse ? bar.surfaceHover : "transparent"

                    Behavior on implicitWidth {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }

                    Behavior on color {
                        ColorAnimation { duration: 120 }
                    }

                    Text {
                        id: workspaceLabel
                        anchors {
                            fill: parent
                            leftMargin: 7
                            rightMargin: 7
                        }
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: workspaceButton.workspaceName
                        color: workspaceButton.active
                            ? bar.background
                            : workspaceButton.occupied ? bar.foreground : bar.muted
                        font.family: "Comic Code"
                        font.pixelSize: 12
                        font.weight: workspaceButton.active ? Font.DemiBold : Font.Medium
                    }

                    MouseArea {
                        id: workspaceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Hyprland.dispatch(Hyprland.usingLua
                            ? "hl.dsp.focus({ workspace = " + workspaceButton.workspaceId + " })"
                            : "workspace " + workspaceButton.workspaceId)
                    }
                }
            }

            Rectangle {
                implicitWidth: 1
                implicitHeight: 13
                color: bar.border
                opacity: 0.8
            }

            UsageSlot {
                backgroundColor: bar.background
                foregroundColor: bar.foreground
                mutedColor: bar.muted
                accentColor: bar.accent
                hoverColor: bar.surfaceHover
                panelWindow: bar
                tooltipBelow: !bar.isTopMonitor
            }

        }

        // Vitals follow the AI slot, then glide over to the right-hand cluster
        // while the slot is expanded. Both separators always take space (only
        // the inward-facing one is shown) so the width stays put mid-slide.
        // Only the toggle animates; cluster geometry changes (tray icons, workspace
        // names) move the dock instantly. `atRight` is set after `sliding`, so the
        // Behavior is already enabled when x changes.
        Item {
            id: vitalsDock

            readonly property bool docksRight: UsageSlotState.expanded
            property bool atRight: false
            property bool sliding: false

            width: vitalsRow.implicitWidth
            height: 22
            anchors.verticalCenter: parent.verticalCenter
            x: atRight
                ? rightCluster.x - width - 2
                : leftCluster.x + leftCluster.width + 2

            Behavior on x {
                enabled: vitalsDock.sliding
                NumberAnimation { duration: 420; easing.type: Easing.InOutCubic }
            }

            SequentialAnimation {
                id: vitalsFade
                NumberAnimation { target: vitalsDock; property: "opacity"; to: 0.15; duration: 170; easing.type: Easing.OutQuad }
                NumberAnimation { target: vitalsDock; property: "opacity"; to: 1; duration: 250; easing.type: Easing.InQuad }
            }

            Timer {
                id: slideEnd
                interval: 440
                onTriggered: vitalsDock.sliding = false
            }

            onDocksRightChanged: {
                sliding = true
                atRight = docksRight
                vitalsFade.restart()
                slideEnd.restart()
            }
            Component.onCompleted: atRight = docksRight

            Row {
                id: vitalsRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 1
                    implicitHeight: 13
                    color: bar.border
                    opacity: vitalsDock.atRight ? 0 : 0.8
                }

                SystemVitals {
                    backgroundColor: bar.background
                    foregroundColor: bar.foreground
                    mutedColor: bar.muted
                    accentColor: bar.accent
                    hoverColor: bar.surfaceHover
                    panelWindow: bar
                    tooltipBelow: !bar.isTopMonitor
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 1
                    implicitHeight: 13
                    color: bar.border
                    opacity: vitalsDock.atRight ? 0.8 : 0
                }
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min((LayoutState.visible ? layoutText.implicitWidth : titleText.implicitWidth) + 18, bar.width * 0.3)
            height: 22
            radius: 0
            color: bar.surface

            Text {
                id: titleText
                anchors {
                    fill: parent
                    leftMargin: 9
                    rightMargin: 9
                }
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: !LayoutState.visible
                text: ToplevelManager.activeToplevel?.title || "desktop"
                color: ToplevelManager.activeToplevel ? bar.foreground : bar.muted
                font.family: "Comic Code"
                font.pixelSize: 11
                font.weight: Font.Medium
            }

            Text {
                id: layoutText
                anchors {
                    fill: parent
                    leftMargin: 9
                    rightMargin: 9
                }
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                visible: LayoutState.visible
                text: LayoutState.layout
                color: bar.accent
                font.family: "Comic Code"
                font.pixelSize: 11
                font.weight: Font.DemiBold

                transform: Translate {
                    id: layoutShift
                }

                Connections {
                    target: LayoutState

                    function onRevisionChanged() {
                        if (LayoutState.visible)
                            layoutEnter.restart()
                    }
                }

                ParallelAnimation {
                    id: layoutEnter

                    NumberAnimation {
                        target: layoutShift
                        property: "y"
                        from: LayoutState.direction === "down" ? -14 : 14
                        to: 0
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                    NumberAnimation {
                        target: layoutText
                        property: "opacity"
                        from: 0
                        to: 1
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        RowLayout {
            id: rightCluster
            anchors {
                right: parent.right
                rightMargin: 7
                verticalCenter: parent.verticalCenter
            }
            spacing: 7

            Row {
                spacing: 2

                Agents {
                    panelWindow: bar
                }

                GameMode {
                    panelWindow: bar
                }

                Hypridle {
                    panelWindow: bar
                }

                Correction {
                    panelWindow: bar
                }

                Matrix {
                    panelWindow: bar
                }

                Hermes {
                    panelWindow: bar
                }

                LlamaModel {
                    panelWindow: bar
                }

                ExpressVPN {
                    panelWindow: bar
                }

                Tailscale {
                    panelWindow: bar
                }
            }

            Row {
                spacing: 2

                Repeater {
                    model: SystemTray.items

                    TrayItem {
                        required property var modelData
                        item: modelData
                        hoverColor: bar.surfaceHover
                    }
                }
            }

            Text {
                text: bar.monitorName
                color: bar.muted
                font.family: "Comic Code"
                font.pixelSize: 10
            }

            Rectangle {
                implicitWidth: clockText.implicitWidth + 13
                implicitHeight: 22
                radius: 0
                color: bar.surface

                Text {
                    id: clockText
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(clock.date, "ddd  MMM d  HH:mm")
                    color: bar.foreground
                    font.family: "Comic Code"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                SystemClock {
                    id: clock
                    precision: SystemClock.Minutes
                }
            }
        }
    }
}
