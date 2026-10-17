import QtQuick 6.0
import QtQuick.Effects
import Quickshell.Widgets

// Bitwarden vault chip: left click opens the vault menu (the unlock card
// first when locked), right click locks the vault now. States: unlocked
// (normal), locked (dimmed), keyring-locked/unauthenticated/error (warning).
BarChip {
    id: root

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    tooltipText: {
        let text = BitwardenState.tooltip
        if (BitwardenState.unlocked)
            text += "\nLeft click: vault menu — right click: lock now"
        else if (BitwardenState.locked)
            text += BitwardenState.waitingForUnlock
                ? "\nWaiting for unlock…"
                : "\nLeft click: unlock and open vault menu"
        return text
    }
    onClicked: BitwardenState.openMenu()
    onRightClicked: BitwardenState.lockNow()

    IconImage {
        anchors.centerIn: parent
        implicitSize: 14
        source: Qt.resolvedUrl("bitwarden.svg")
        asynchronous: true
        opacity: BitwardenState.locked ? 0.45 : 1.0

        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1.0
            colorizationColor: BitwardenState.unlocked
                ? root.foregroundColor
                : BitwardenState.locked
                    ? root.mutedColor
                    : root.accentColor
        }
    }
}
