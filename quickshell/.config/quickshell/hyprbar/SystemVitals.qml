import QtQuick 6.0

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

    implicitWidth: vitalsText.implicitWidth + 11
    implicitHeight: 22
    radius: 0
    color: vitalsMouse.containsMouse ? root.hoverColor : "transparent"

    Text {
        id: vitalsText
        anchors.centerIn: parent
        text: " " + SystemVitalsState.cpu + "%   " + SystemVitalsState.ram
            + "%  󰋊 " + SystemVitalsState.disk + "%   " + SystemVitalsState.temp
            + "°  󰢮 " + (SystemVitalsState.gpu >= 0 ? SystemVitalsState.gpu + "%" : "—")
        color: root.foregroundColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 11
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
