import QtQuick 6.0
import QtQuick.Effects

// A single fixed-width badge cycles through the providers represented by the
// ai-usage snapshot. Hover shows only the current provider's primary reading.
// Middle-click expands to every provider side by side (and back); the tooltip
// then follows the provider under the pointer.
Rectangle {
    id: root

    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor
    required property color hoverColor
    required property var panelWindow
    property bool tooltipBelow: false
    property int providerIndex: 0

    readonly property var providers: [
        { id: "codex", label: "Codex", shortLabel: "Codex", source: "ai-codex.svg" },
        { id: "claude_code", label: "Claude", shortLabel: "Claude", source: "ai-claude.svg" },
        { id: "antigravity", label: "Antigravity", shortLabel: "Antig.", source: "ai-antigravity.svg" },
        { id: "zai", label: "Z.AI", shortLabel: "Z.AI", source: "ai-zai.svg" },
        { id: "pi", label: "Pi", shortLabel: "Pi", source: "" },
        { id: "hermes", label: "Hermes", shortLabel: "Hermes", source: "" },
        { id: "openrouter", label: "OpenRouter", shortLabel: "Router", source: "ai-openrouter.svg" }
    ]
    readonly property var currentInfo: providers[providerIndex]
    readonly property var currentProvider: currentInfo
        ? AiUsageState.providerFor(currentInfo.id) : null
    readonly property var hoveredInfo: {
        if (!UsageSlotState.expanded || !slotMouse.containsMouse)
            return null
        const item = expandedRow.childAt(slotMouse.mouseX - expandedRow.x, expandedRow.height / 2)
        return item && item.modelData ? item.modelData : null
    }
    // Gaps between icons keep the last provider so the tooltip neither blanks
    // nor flickers, and its provider never flips to null mid-fade.
    property var lastHoveredInfo: null
    onHoveredInfoChanged: if (hoveredInfo) lastHoveredInfo = hoveredInfo
    readonly property var tooltipInfo: UsageSlotState.expanded
        ? (lastHoveredInfo || currentInfo) : currentInfo

    function formatLeft(value) {
        if (value === undefined || value === null || String(value).length === 0)
            return "?"
        const percent = Number(value)
        if (!isFinite(percent))
            return "?"
        return percent < 10 || (percent >= 99.5 && percent < 100)
            ? percent.toFixed(1) + "%" : Math.round(percent) + "%"
    }

    function primaryValue(provider) {
        if (!provider)
            return "—"

        if (provider.id === "hermes") {
            const rawTokens = AiUsageState.tokenUsage.hermes_today
            const tokens = rawTokens === null || rawTokens === undefined ? NaN : Number(rawTokens)
            if (!isFinite(tokens))
                return "?"
            return tokens >= 1000000
                ? (tokens / 1000000).toFixed(1) + "M"
                : tokens >= 1000 ? Math.round(tokens / 1000) + "K" : String(Math.round(tokens))
        }

        if (provider.id === "openrouter") {
            const amount = provider.remaining === null || provider.remaining === undefined
                ? NaN : Number(provider.remaining)
            if (!isFinite(amount))
                return "?"
            return "$" + (amount >= 100 ? Math.round(amount) : amount.toFixed(2))
        }

        if (provider.five_hour_left !== null && provider.five_hour_left !== undefined)
            return formatLeft(provider.five_hour_left)

        const details = String(provider.details || "")
        const cost = details.match(/\$[0-9]+(?:\.[0-9]+)? used/)
        if (cost)
            return cost[0].replace(" used", "")

        const tokens = details.match(/([0-9,]+) total tokens/)
        if (tokens) {
            const count = Number(tokens[1].replace(/,/g, ""))
            if (isFinite(count))
                return count >= 1000000
                    ? (count / 1000000).toFixed(1) + "M"
                    : count >= 1000 ? Math.round(count / 1000) + "K" : String(count)
        }

        return "?"
    }

    function secondaryValue(provider) {
        if (!provider || provider.seven_day_left === null || provider.seven_day_left === undefined)
            return ""
        return "7d " + formatLeft(provider.seven_day_left)
            + "  " + String(provider.weekly_reset_short || "?")
    }

    implicitWidth: UsageSlotState.expanded ? expandedRow.implicitWidth + 12 : 116
    implicitHeight: 22
    radius: 0
    color: slotMouse.containsMouse ? root.hoverColor : "transparent"

    Row {
        id: compactRow
        visible: !UsageSlotState.expanded
        anchors {
            left: parent.left
            leftMargin: 6
            right: parent.right
            rightMargin: 6
            verticalCenter: parent.verticalCenter
        }
        height: parent.height
        spacing: 5

        Item {
            width: 14
            height: 22
            anchors.verticalCenter: parent.verticalCenter

            Image {
                anchors.centerIn: parent
                width: 13
                height: 13
                source: root.currentInfo && root.currentInfo.source.length > 0
                    ? Qt.resolvedUrl(root.currentInfo.source) : ""
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                visible: source.toString().length > 0

                layer.enabled: visible
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: root.foregroundColor
                }
            }

            Text {
                anchors.centerIn: parent
                visible: !root.currentInfo || root.currentInfo.source.length === 0
                text: root.currentInfo ? root.currentInfo.label.slice(0, 1) : "?"
                color: root.foregroundColor
                font.family: "Comic Code"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }

        // The label yields space to the value so a balance like "$82.13" is
        // never elided; the badge itself keeps its fixed width.
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: compactRow.width - 14 - valueText.implicitWidth - 2 * compactRow.spacing
            text: root.currentInfo ? root.currentInfo.shortLabel : "AI"
            color: root.foregroundColor
            font.family: "Comic Code"
            font.pixelSize: 10
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Text {
            id: valueText
            anchors.verticalCenter: parent.verticalCenter
            text: root.primaryValue(root.currentProvider)
            color: text === "?" || text === "—" ? root.mutedColor : root.accentColor
            font.family: "Comic Code"
            font.pixelSize: 10
        }
    }

    Row {
        id: expandedRow
        visible: UsageSlotState.expanded
        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        spacing: 7

        Repeater {
            model: root.providers

            delegate: Item {
                required property var modelData
                readonly property var provider: AiUsageState.providerFor(modelData.id)
                width: provider ? providerRow.implicitWidth : 0
                height: 22
                visible: provider !== null

                Row {
                    id: providerRow
                    height: parent.height
                    spacing: 2

                    Item {
                        width: 13
                        height: parent.height

                        Image {
                            // Integer y avoids half-pixel softness: (22 - 13) / 2 -> 5.
                            y: Math.round((parent.height - height) / 2)
                            width: 13
                            height: 13
                            source: modelData.source.length > 0 ? Qt.resolvedUrl(modelData.source) : ""
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            visible: modelData.source.length > 0

                            layer.enabled: visible
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: root.foregroundColor
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: modelData.source.length === 0
                            text: modelData.label.slice(0, 1)
                            color: root.foregroundColor
                            font.family: "Comic Code"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: -1

                        Text {
                            text: root.primaryValue(provider)
                            color: text === "?" || text === "—" ? root.mutedColor : root.foregroundColor
                            font.family: "Comic Code"
                            font.pixelSize: 11
                        }

                        Text {
                            visible: text.length > 0
                            text: root.secondaryValue(provider)
                            color: root.mutedColor
                            font.family: "Comic Code"
                            font.pixelSize: 8
                        }
                    }
                }
            }
        }
    }

    MouseArea {
        id: slotMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                aiPanel.shown = !aiPanel.shown
            else if (mouse.button === Qt.MiddleButton)
                UsageSlotState.toggle()
            else
                AiUsageState.refresh()
        }
    }

    Timer {
        interval: 4500
        running: !UsageSlotState.expanded && root.providers.length > 1
        repeat: true
        onTriggered: root.providerIndex = (root.providerIndex + 1) % root.providers.length
    }

    AiPanel {
        id: aiPanel
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
        mutedColor: root.mutedColor
        accentColor: root.accentColor
    }

    ProviderTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: slotMouse.containsMouse
        provider: root.tooltipInfo ? AiUsageState.providerFor(root.tooltipInfo.id) : null
        providerInfo: root.tooltipInfo
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
        mutedColor: root.mutedColor
        accentColor: root.accentColor
    }
}
