import QtQuick 6.0
import QtQuick.Effects
import Quickshell.Widgets

// Compact read-only host resource summary.
Rectangle {
    id: root

    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor
    required property color hoverColor
    required property var panelWindow
    property bool tooltipBelow: false

    implicitWidth: vitalsRow.implicitWidth + 11
    implicitHeight: 22
    radius: 0
    color: vitalsMouse.containsMouse ? root.hoverColor : "transparent"

    Row {
        id: vitalsRow

        anchors.centerIn: parent
        spacing: 8

        Row {
            spacing: 3

            IconImage {
                id: cpuIcon

                implicitSize: 13
                source: Qt.resolvedUrl("cpu.svg")
                asynchronous: true

                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.foregroundColor
                }
            }

            Text {
                anchors.verticalCenter: cpuIcon.verticalCenter
                text: SystemVitalsState.cpu + "%"
                color: root.foregroundColor
                font.family: "Comic Code"
                font.pixelSize: 11
            }
        }

        Row {
            spacing: 3

            IconImage {
                id: ramIcon

                implicitSize: 13
                source: Qt.resolvedUrl("ram.svg")
                asynchronous: true

                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.foregroundColor
                }
            }

            Text {
                anchors.verticalCenter: ramIcon.verticalCenter
                text: SystemVitalsState.ram + "%"
                color: root.foregroundColor
                font.family: "Comic Code"
                font.pixelSize: 11
            }
        }

        Row {
            spacing: 3

            IconImage {
                id: diskIcon

                implicitSize: 13
                source: Qt.resolvedUrl("disk.svg")
                asynchronous: true

                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.foregroundColor
                }
            }

            Text {
                anchors.verticalCenter: diskIcon.verticalCenter
                text: SystemVitalsState.disk + "%"
                color: root.foregroundColor
                font.family: "Comic Code"
                font.pixelSize: 11
            }
        }

        Row {
            spacing: 3

            IconImage {
                id: thermIcon

                implicitSize: 13
                source: Qt.resolvedUrl("therm.svg")
                asynchronous: true

                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.foregroundColor
                }
            }

            Text {
                anchors.verticalCenter: thermIcon.verticalCenter
                text: SystemVitalsState.temp + "°"
                color: root.foregroundColor
                font.family: "Comic Code"
                font.pixelSize: 11
            }
        }

        Row {
            spacing: 3

            IconImage {
                id: gpuIcon

                implicitSize: 13
                source: Qt.resolvedUrl("gpu.svg")
                asynchronous: true

                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: SystemVitalsState.gpu >= 0 ? root.foregroundColor : root.mutedColor
                }
            }

            Text {
                anchors.verticalCenter: gpuIcon.verticalCenter
                text: SystemVitalsState.gpu >= 0 ? SystemVitalsState.gpu + "%" : "—"
                color: SystemVitalsState.gpu >= 0 ? root.foregroundColor : root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 11
            }
        }
    }

    MouseArea {
        id: vitalsMouse
        anchors.fill: parent
        hoverEnabled: true
    }

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: vitalsMouse.containsMouse
        labelText: "CPU " + SystemVitalsState.cpu + "%  •  RAM " + SystemVitalsState.ram
            + "%  •  / " + SystemVitalsState.disk + "%\n"
            + "Temp " + SystemVitalsState.temp + "°C  •  GPU "
            + (SystemVitalsState.gpu >= 0
                ? SystemVitalsState.gpu + "% / " + SystemVitalsState.gpuTemp + "°C"
                : "unavailable")
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
