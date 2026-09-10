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
    implicitHeight: 24
    exclusiveZone: 24

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
            anchors {
                left: parent.left
                leftMargin: 8
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

                    implicitWidth: Math.max(26, Math.min(128, workspaceLabel.implicitWidth + 16))
                    implicitHeight: 24
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
                            leftMargin: 8
                            rightMargin: 8
                        }
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: workspaceButton.workspaceName
                        color: workspaceButton.active
                            ? bar.background
                            : workspaceButton.occupied ? bar.foreground : bar.muted
                        font.family: "monospace"
                        font.pixelSize: 13
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
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(titleText.implicitWidth + 20, bar.width * 0.34)
            height: 24
            radius: 0
            color: "transparent"

            Text {
                id: titleText
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 10
                }
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: ToplevelManager.activeToplevel?.title || "desktop"
                color: ToplevelManager.activeToplevel ? bar.foreground : bar.muted
                font.family: "monospace"
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        RowLayout {
            anchors {
                right: parent.right
                rightMargin: 8
                verticalCenter: parent.verticalCenter
            }
            spacing: 8

            Row {
                spacing: 2

                CpuGovernor {
                    backgroundColor: bar.background
                    foregroundColor: bar.foreground
                    mutedColor: bar.muted
                    accentColor: bar.accent
                    hoverColor: bar.surfaceHover
                    panelWindow: bar
                    tooltipBelow: !bar.isTopMonitor
                }

                GameMode {
                    backgroundColor: bar.background
                    foregroundColor: bar.foreground
                    mutedColor: bar.muted
                    accentColor: bar.accent
                    hoverColor: bar.surfaceHover
                    panelWindow: bar
                    tooltipBelow: !bar.isTopMonitor
                }

                // ExpressVPN status and toggle.
                ExpressVPN {
                    backgroundColor: bar.background
                    foregroundColor: bar.foreground
                    mutedColor: bar.muted
                    accentColor: bar.accent
                    hoverColor: bar.surfaceHover
                    panelWindow: bar
                    tooltipBelow: !bar.isTopMonitor
                }

                Tailscale {
                    backgroundColor: bar.background
                    foregroundColor: bar.foreground
                    mutedColor: bar.muted
                    accentColor: bar.accent
                    hoverColor: bar.surfaceHover
                    panelWindow: bar
                    tooltipBelow: !bar.isTopMonitor
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
                font.family: "monospace"
                font.pixelSize: 11
            }

            Rectangle {
                implicitWidth: clockText.implicitWidth + 14
                implicitHeight: 24
                radius: 0
                color: "transparent"

                Text {
                    id: clockText
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(clock.date, "ddd  MMM d  HH:mm")
                    color: bar.foreground
                    font.family: "monospace"
                    font.pixelSize: 12
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
