import QtQuick 6.0
import QtQuick.Effects
import Quickshell.Widgets

// The left status slot toggles between host vitals and aggregate AI usage.
Rectangle {
    id: root

    required property color backgroundColor
    required property color foregroundColor
    required property color mutedColor
    required property color accentColor
    required property color hoverColor
    required property var panelWindow
    property bool tooltipBelow: false

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

        if (provider.id === "openrouter") {
            const rawBalance = provider.remaining !== undefined && provider.remaining !== null
                ? String(provider.remaining).trim() : ""
            const balance = rawBalance.length > 0 ? Number(rawBalance.replace("$", "")) : NaN
            if (isFinite(balance))
                return "$" + (balance >= 100 ? Math.round(balance) : balance.toFixed(2))
            if (rawBalance.startsWith("$"))
                return rawBalance
            return "$?"
        }

        if (provider.five_hour_left == null)
            return "?"

        return root.formatLeft(provider.five_hour_left)
    }

    function secondaryValue(provider) {
        if (!provider || provider.seven_day_left == null)
            return ""
        return "7d " + root.formatLeft(provider.seven_day_left)
            + "  " + String(provider.weekly_reset_short || "?")
    }

    readonly property int slotWidth: UsageSlotState.showingAiUsage
        ? aiView.implicitWidth + switchIndicator.implicitWidth + 15
        : vitalsView.implicitWidth + 12
    implicitWidth: root.slotWidth
    implicitHeight: 22
    radius: 0
    color: slotMouse.containsMouse ? root.hoverColor : "transparent"

    SystemVitals {
        id: vitalsView
        anchors.fill: parent
        anchors.rightMargin: 12
        visible: !UsageSlotState.showingAiUsage
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
        mutedColor: root.mutedColor
        accentColor: root.accentColor
        hoverColor: root.hoverColor
        panelWindow: root.panelWindow
        tooltipBelow: root.tooltipBelow
    }

    Row {
        id: aiView
        anchors.left: parent.left
        anchors.leftMargin: 5
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7
        visible: UsageSlotState.showingAiUsage

        Repeater {
            model: [
                { id: "codex", source: "ai-codex.svg" },
                { id: "claude_code", source: "ai-claude.svg" },
                { id: "antigravity", source: "ai-antigravity.svg" },
                { id: "zai", source: "ai-zai.svg" },
                { id: "openrouter", source: "ai-openrouter.svg" }
            ]

            delegate: Item {
                required property var modelData
                readonly property var provider: AiUsageState.providerFor(modelData.id)
                width: provider ? providerRow.implicitWidth : 0
                height: 22
                visible: provider !== null

                Row {
                    id: providerRow
                    // Fixed row height pins every logo to the delegate's centre,
                    // whether or not the provider has a secondary line.
                    height: parent.height
                    spacing: 2

                    Image {
                        // Integer y avoids half-pixel softness: (22 - 13) / 2 -> 5.
                        y: Math.round((parent.height - height) / 2)
                        width: 13
                        height: 13
                        source: Qt.resolvedUrl(modelData.source)
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: root.foregroundColor
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: -1

                        Text {
                            text: root.primaryValue(provider)
                            color: root.primaryValue(provider).indexOf("?") >= 0
                                ? root.mutedColor : root.foregroundColor
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

    Text {
        id: switchIndicator
        anchors.right: parent.right
        anchors.rightMargin: 2
        anchors.verticalCenter: parent.verticalCenter
        text: "⇄"
        color: UsageSlotState.showingAiUsage ? root.accentColor : root.mutedColor
        font.family: "Symbols Nerd Font Mono"
        font.pixelSize: 10
    }

    MouseArea {
        id: slotMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton && UsageSlotState.showingAiUsage)
                aiPanel.shown = !aiPanel.shown
            else
                UsageSlotState.toggle()
        }
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

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: slotMouse.containsMouse
        labelText: UsageSlotState.showingAiUsage
            ? AiUsageState.tooltip
            : "SYSTEM VITALS\n"
                + "CPU     " + SystemVitalsState.cpu + "%\n"
                + "RAM     " + SystemVitalsState.ram + "%\n"
                + "DISK    " + SystemVitalsState.disk + "%\n"
                + "TEMP    " + SystemVitalsState.temp + "°C\n"
                + "GPU     " + (SystemVitalsState.gpu >= 0
                    ? SystemVitalsState.gpu + "%  /  " + SystemVitalsState.gpuTemp + "°C"
                    : "unavailable")
                + "\nLeft-click to show AI usage"
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
