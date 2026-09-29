import Quickshell
import QtQuick 6.0
import QtQuick.Effects

// DHH-style agents panel for the bar's AI usage slot: one block per provider
// with logo, remaining quota meters, and reset countdowns. Data comes from the
// same ai-usage collector as the bar logos via AiUsageState; this component is
// read-only presentation and owns no provider access.
PopupWindow {
    id: root

    required property var panelWindow
    required property var triggerItem
    required property bool below
    property bool shown: false
    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor

    // The wallust palette carries no alarm hue, so the >=90%-used urgent red is
    // fixed; it stays readable on both dark and light palettes.
    readonly property color urgent: "#e5534b"
    readonly property color track: Qt.alpha(root.foregroundColor, 0.16)

    // Countdowns read this clock instead of Date.now() so an open panel keeps
    // telling the truth while it sits open.
    property date now: new Date()

    readonly property var providers: [
        { id: "codex", label: "Codex", source: "ai-codex.svg" },
        { id: "claude_code", label: "Claude", source: "ai-claude.svg" },
        { id: "antigravity", label: "Antigravity", source: "ai-antigravity.svg" },
        { id: "zai", label: "Z.AI", source: "ai-zai.svg" },
        { id: "openrouter", label: "OpenRouter", source: "ai-openrouter.svg" }
    ]

    Timer {
        interval: 30000
        running: root.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

    onShownChanged: {
        if (shown) {
            root.now = new Date()
            AiUsageState.refresh()
        }
    }

    function fmtRemaining(iso) {
        if (!iso)
            return ""
        const when = Date.parse(iso)
        if (isNaN(when))
            return ""
        let seconds = Math.round((when - root.now.getTime()) / 1000)
        if (seconds <= 0)
            return "now"
        const days = Math.floor(seconds / 86400)
        seconds -= days * 86400
        const hours = Math.floor(seconds / 3600)
        seconds -= hours * 3600
        const minutes = Math.floor(seconds / 60)
        if (days > 0)
            return days + "d " + hours + "h"
        if (hours > 0)
            return hours + "h " + minutes + "m"
        return minutes + "m"
    }

    function fmtPercent(value) {
        if (value === null || value === undefined)
            return "—"
        const percent = Number(value)
        if (!isFinite(percent))
            return "—"
        return percent < 10 || (percent >= 99.5 && percent < 100)
            ? percent.toFixed(1) + "%" : Math.round(percent) + "%"
    }

    function updatedLabel() {
        const when = Date.parse(AiUsageState.updatedAt)
        const stamp = isNaN(when)
            ? "—"
            : Qt.formatDateTime(new Date(when), "HH:mm")
        return "updated " + stamp + (AiUsageState.stale ? " · stale" : "")
    }

    anchor.window: root.panelWindow
    anchor.item: root.triggerItem
    anchor.rect.x: Math.max(4, Math.round((root.triggerItem.width - root.implicitWidth) / 2))
    anchor.rect.y: root.below ? root.triggerItem.height + 4 : -root.implicitHeight - 4

    visible: root.shown
    color: "transparent"
    implicitWidth: 380
    implicitHeight: panelColumn.implicitHeight + 20

    Rectangle {
        anchors.fill: parent
        color: root.backgroundColor
        border.color: root.foregroundColor
        border.width: 1

        // Any click inside the panel dismisses it; the slot's right-click also
        // toggles. Nothing inside the panel is interactive.
        MouseArea {
            anchors.fill: parent
            onClicked: root.shown = false
        }

        Column {
            id: panelColumn
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: 10
            }
            spacing: 7

            Item {
                width: parent.width
                height: headerLabel.implicitHeight

                Text {
                    id: headerLabel
                    text: "AI USAGE"
                    color: root.accentColor
                    font.family: "Comic Code"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Text {
                    anchors.right: closeButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.updatedLabel()
                    color: root.mutedColor
                    font.family: "Comic Code"
                    font.pixelSize: 9
                }

                Text {
                    id: closeButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "×"
                    color: root.mutedColor
                    font.family: "Comic Code"
                    font.pixelSize: 12

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.shown = false
                    }
                }
            }

            Repeater {
                model: root.providers

                delegate: Column {
                    id: providerBlock

                    required property var modelData
                    required property int index
                    readonly property var provider: AiUsageState.providerFor(modelData.id)
                    readonly property bool hasQuota: provider !== null
                        && (provider.five_hour_left != null || provider.seven_day_left != null)
                    readonly property bool isCredit: modelData.id === "openrouter"

                    width: parent.width
                    spacing: 4

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.track
                        visible: providerBlock.index > 0
                    }

                    Item {
                        width: parent.width
                        height: 16

                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 13
                                height: 13
                                source: Qt.resolvedUrl(providerBlock.modelData.source)
                                asynchronous: true
                                fillMode: Image.PreserveAspectFit
                                visible: providerBlock.provider !== null

                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: root.foregroundColor
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: providerBlock.modelData.label
                                color: root.foregroundColor
                                font.family: "Comic Code"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                const provider = providerBlock.provider
                                if (provider === null)
                                    return "no data"
                                if (providerBlock.isCredit) {
                                    const raw = provider.remaining !== undefined
                                        && provider.remaining !== null
                                        ? String(provider.remaining).trim() : ""
                                    const balance = raw.length > 0
                                        ? Number(raw.replace("$", "")) : NaN
                                    return isFinite(balance)
                                        ? "$" + (balance >= 100
                                            ? Math.round(balance) : balance.toFixed(2))
                                        : "unavailable"
                                }
                                if (provider.five_hour_left == null)
                                    return provider.details === "unavailable"
                                        ? "unavailable" : "no quota data"
                                return root.fmtPercent(provider.five_hour_left) + " left"
                            }
                            color: {
                                const provider = providerBlock.provider
                                if (provider === null)
                                    return root.mutedColor
                                if (providerBlock.isCredit)
                                    return provider.remaining != null
                                        ? root.foregroundColor : root.mutedColor
                                if (provider.five_hour_left == null)
                                    return root.mutedColor
                                return provider.five_hour_left < 10
                                    ? root.urgent : root.foregroundColor
                            }
                            font.family: "Comic Code"
                            font.pixelSize: 10
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 3
                        visible: providerBlock.hasQuota

                        Repeater {
                            model: providerBlock.hasQuota ? [
                                {
                                    label: "5h",
                                    left: providerBlock.provider?.five_hour_left ?? null,
                                    reset: providerBlock.provider?.five_hour_reset ?? null
                                },
                                {
                                    label: "7d",
                                    left: providerBlock.provider?.seven_day_left ?? null,
                                    reset: providerBlock.provider?.weekly_reset ?? null
                                }
                            ] : []

                            delegate: Item {
                                id: meterRow

                                required property var modelData
                                readonly property real ratio: modelData.left != null
                                    ? Math.max(0, Math.min(1, Number(modelData.left) / 100)) : 0
                                readonly property bool alarming: modelData.left != null
                                    && Number(modelData.left) < 10
                                readonly property string countdown: {
                                    const left = root.fmtRemaining(modelData.reset)
                                    return left.length > 0 ? "resets in " + left : ""
                                }

                                width: parent.width
                                height: 12

                                Text {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: meterRow.modelData.label
                                    color: root.mutedColor
                                    font.family: "Comic Code"
                                    font.pixelSize: 8
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 20
                                    anchors.right: meterCountdown.left
                                    anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 4
                                    radius: 2
                                    color: root.track

                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: Math.round(parent.width * meterRow.ratio)
                                        radius: 2
                                        color: meterRow.alarming ? root.urgent : root.foregroundColor

                                        Behavior on width {
                                            NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                        }
                                    }
                                }

                                Text {
                                    id: meterCountdown
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: meterRow.countdown
                                    color: root.mutedColor
                                    font.family: "Comic Code"
                                    font.pixelSize: 8
                                }
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: "left-click bar slot: switch views · right-click: this panel"
                color: root.mutedColor
                font.family: "Comic Code"
                font.pixelSize: 8
            }
        }
    }
}
