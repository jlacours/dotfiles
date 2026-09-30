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
    readonly property bool hasFiveHour: provider
        && provider.five_hour_left !== null && provider.five_hour_left !== undefined
    readonly property bool hasSevenDay: provider
        && provider.seven_day_left !== null && provider.seven_day_left !== undefined
    readonly property bool hasQuota: isCredit
        ? provider && provider.percent !== null && provider.percent !== undefined
        : hasFiveHour || hasSevenDay
    readonly property real primaryLeft: hasFiveHour
        ? Number(provider.five_hour_left)
        : hasSevenDay ? Number(provider.seven_day_left) : 0
    readonly property real percentUsed: {
        if (!provider)
            return 0
        const used = isCredit ? Number(provider.percent) : 100 - primaryLeft
        return isFinite(used) ? Math.max(0, Math.min(100, used)) : 0
    }
    readonly property color urgent: "#e5534b"
    readonly property color meterColor: !isCredit && primaryLeft < 10
        ? urgent : accentColor

    function formatPercent(value) {
        const percent = Number(value)
        if (!isFinite(percent))
            return "—"
        return percent < 10 || (percent >= 99.5 && percent < 100)
            ? percent.toFixed(1) + "%" : Math.round(percent) + "%"
    }

    function resetTime(value) {
        if (!value)
            return ""
        const when = Date.parse(value)
        if (isNaN(when))
            return ""
        return Qt.formatDateTime(new Date(when), "h:mm AP")
    }

    function resetDate(value) {
        if (!value)
            return ""
        const when = Date.parse(value)
        if (isNaN(when))
            return ""
        const date = new Date(when)
        return Qt.formatDateTime(date, date.getFullYear() === root.now.getFullYear()
            ? "MMM d" : "MMM d, yyyy")
    }

    function formatTokens(value) {
        if (value === null || value === undefined || !isFinite(Number(value)))
            return "unavailable"
        return String(Math.round(Number(value))).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
    }

    function coverageLabel(tracked) {
        const total = Number(root.tokenUsage.harness_count || 6)
        return Number(tracked || 0) >= total ? "complete" : "partial"
    }

    readonly property string detailText: {
        if (!provider)
            return "Usage unavailable"
        if (providerInfo && providerInfo.id === "hermes") {
            const amount = AiUsageState.tokenUsage.hermes_today
            return amount === null || amount === undefined
                ? "Today · token usage unavailable"
                : "Today · " + formatTokens(amount) + " tokens (sessions opened today)"
        }
        if (isCredit) {
            const amount = provider.remaining === null || provider.remaining === undefined
                ? NaN : Number(provider.remaining)
            return isFinite(amount) ? "$" + amount.toFixed(2) + " credit left" : "Credit unavailable"
        }
        if (hasFiveHour || hasSevenDay)
            return ""
        return String(provider.details || "Usage unavailable")
    }

    readonly property var tokenUsage: AiUsageState.tokenUsage || ({})

    readonly property string resetAvailability: {
        if (!provider || provider.reset_available === undefined || provider.reset_available === null)
            return ""
        if (typeof provider.reset_available === "boolean")
            return provider.reset_available ? "Reset available" : "Reset unavailable"
        return String(provider.reset_available)
    }

    anchor.window: root.panelWindow
    anchor.item: root.triggerItem
    anchor.rect.x: Math.max(4, Math.round((root.triggerItem.width - root.implicitWidth) / 2))
    anchor.rect.y: root.below ? root.triggerItem.height + 4 : -root.implicitHeight - 4

    visible: root.shown || root.fadeOpacity > 0.01
    color: "transparent"
    implicitWidth: 270
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
                id: detailLabel
                text: root.detailText
                color: root.provider ? root.foregroundColor : root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 10
                elide: Text.ElideRight
                width: parent.width
                visible: text.length > 0
            }

            Text {
                text: "5h " + root.formatPercent(root.provider?.five_hour_left)
                    + " left" + (root.resetTime(root.provider?.five_hour_reset).length > 0
                        ? " · reset at " + root.resetTime(root.provider.five_hour_reset) : "")
                color: root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 9
                elide: Text.ElideRight
                width: parent.width
                visible: root.hasFiveHour
            }

            Text {
                text: "7d " + root.formatPercent(root.provider?.seven_day_left)
                    + " left" + (root.resetDate(root.provider?.weekly_reset).length > 0
                        ? " · reset " + root.resetDate(root.provider.weekly_reset) : "")
                color: root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 9
                elide: Text.ElideRight
                width: parent.width
                visible: root.hasSevenDay
            }

            Text {
                text: "· " + root.resetAvailability
                color: root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 9
                visible: root.resetAvailability.length > 0
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

            Rectangle {
                width: parent.width
                height: 1
                color: Qt.alpha(root.foregroundColor, 0.16)
            }

            Text {
                text: "Harness tokens"
                color: root.accentColor
                font.family: "Comic Code"
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }

            Text {
                text: "Today " + root.formatTokens(root.tokenUsage.today_total)
                    + " · " + root.coverageLabel(root.tokenUsage.today_tracked)
                    + " " + Number(root.tokenUsage.today_tracked || 0)
                    + "/" + Number(root.tokenUsage.harness_count || 6)
                color: root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 9
            }

            Text {
                text: "All-time " + root.formatTokens(root.tokenUsage.all_time_total)
                    + " · " + root.coverageLabel(root.tokenUsage.all_time_tracked)
                    + " " + Number(root.tokenUsage.all_time_tracked || 0)
                    + "/" + Number(root.tokenUsage.harness_count || 6)
                color: root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 9
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
