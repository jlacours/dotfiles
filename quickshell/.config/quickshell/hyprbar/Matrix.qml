import QtQuick 6.0
import QtQuick.Effects
import Quickshell.Widgets

// Local Matrix homeserver and its Hermes gateway.
BarChip {
    id: root

    tooltipText: MatrixState.tooltip
    clickEnabled: MatrixState.available && !MatrixState.busy
    cursorShape: root.clickEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: MatrixState.toggle()

    IconImage {
        anchors.centerIn: parent
        implicitSize: 16
        source: Qt.resolvedUrl("matrix-mask.svg")
        asynchronous: true
        opacity: MatrixState.busy ? 0.55
            : MatrixState.active ? 1.0
            : MatrixState.partial ? 0.8 : 0.55

        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: root.accentColor
        }

        SequentialAnimation on opacity {
            loops: Animation.Infinite
            running: MatrixState.busy
            NumberAnimation { to: 0.35; duration: 450 }
            NumberAnimation { to: 1.0; duration: 450 }
        }
    }
}
