import Quickshell
import QtQuick 6.0

// A compact hover card for the currently rotating provider: one primary quota
// meter, not the full multi-provider report. Reset information is read-only.
PopupWindow {
    id: root

    required property var panelWindow
    required property var triggerItem
    required property bool below
    required property bool shown
    required property var provider
    required property var providerInfo
    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor

    property date now: new Date()
    property real fadeOpacity: 0
    readonly property bool isCredit: providerInfo && providerInfo.id === "openrouter"
    readonly property bool hasQuota: provider && (isCredit
        ? provider.percent !== null && provider.percent !== undefined
        : provider.five_hour_left !== null && provider.five_hour_left !== undefined)
    readonly property real percentUsed: {
        if (!provider)
            return 0
        const used = isCredit ? Number(provider.percent) : 100 - Number(provider.five_hour_left)
        return isFinite(used) ? Math.max(0, Math.min(100, used)) : 0
    }
    readonly property color urgent: "#e5534b"
    readonly property color meterColor: !isCredit && Number(provider?.five_hour_left) < 10
        ? urgent : accentColor

    function formatPercent(value) {
        const percent = Number(value)
        if (!isFinite(percent))
            return "—"
        return percent < 10 || (percent >= 99.5 && percent < 100)
            ? percent.toFixed(1) + "%" : Math.round(percent) + "%"
    }

    function resetCountdown(value) {
        if (!value)
            return ""
        const when = Date.parse(value)
        if (isNaN(when))
            return ""
        let seconds = Math.max(0, Math.floor((when - root.now.getTime()) / 1000))
        if (seconds === 0)
            return "Resets now"
        const hours = Math.floor(seconds / 3600)
        const minutes = Math.floor((seconds % 3600) / 60)
        const days = Math.floor(hours / 24)
        if (days > 0)
            return "Resets in " + days + "d " + (hours % 24) + "h"
        if (hours > 0)
            return "Resets in " + hours + "h " + minutes + "m"
        return "Resets in " + minutes + "m"
    }

    readonly property string detailText: {
        if (!provider)
            return "Usage unavailable"
        if (isCredit) {
            const amount = provider.remaining === null || provider.remaining === undefined
                ? NaN : Number(provider.remaining)
            return isFinite(amount) ? "$" + amount.toFixed(2) + " credit left" : "Credit unavailable"
        }
        if (provider.five_hour_left !== null && provider.five_hour_left !== undefined)
            return "5h  " + formatPercent(provider.five_hour_left) + " left"
        return String(provider.details || "Usage unavailable")
    }

    anchor.window: root.panelWindow
    anchor.item: root.triggerItem
    anchor.rect.x: Math.max(4, Math.round((root.triggerItem.width - root.implicitWidth) / 2))
    anchor.rect.y: root.below ? root.triggerItem.height + 4 : -root.implicitHeight - 4

    visible: root.shown || root.fadeOpacity > 0.01
    color: "transparent"
    implicitWidth: 220
    implicitHeight: card.implicitHeight

    onShownChanged: root.fadeOpacity = root.shown ? 1 : 0

    Behavior on fadeOpacity {
        NumberAnimation {
            duration: 380
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        color: root.backgroundColor
        border.color: root.foregroundColor
        border.width: 1
        implicitHeight: cardContent.implicitHeight + 16
        opacity: root.fadeOpacity

        Column {
            id: cardContent
            anchors.fill: parent
            anchors.margins: 8
            spacing: 5

            Text {
                text: root.providerInfo ? root.providerInfo.label : "AI Provider"
                color: root.accentColor
                font.family: "Comic Code"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }

            Text {
                text: root.detailText
                color: root.provider ? root.foregroundColor : root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 10
                elide: Text.ElideRight
                width: parent.width
            }

            Rectangle {
                width: parent.width
                height: 5
                radius: 2
                color: Qt.alpha(root.foregroundColor, 0.16)
                visible: root.hasQuota
                clip: true

                Rectangle {
                    width: parent.width * root.percentUsed / 100
                    height: parent.height
                    radius: parent.radius
                    color: root.meterColor
                }
            }

            Text {
                text: root.isCredit ? "Credit balance" : root.resetCountdown(root.provider?.five_hour_reset)
                color: root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 9
                visible: root.isCredit || (root.hasQuota && text.length > 0)
            }
        }
    }

    Timer {
        interval: 30000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }
}
