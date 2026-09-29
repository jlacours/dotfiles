import QtQuick 6.0
import QtQuick.Effects

// A single fixed-width badge cycles through the providers represented by the
// ai-usage snapshot. The tooltip always shows the complete provider report.
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
            const amount = provider.remaining === null || provider.remaining === undefined
                ? NaN : Number(provider.remaining)
            return isFinite(amount) ? "$" + amount.toFixed(2) : "?"
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

    implicitWidth: 116
    implicitHeight: 22
    radius: 0
    color: slotMouse.containsMouse ? root.hoverColor : "transparent"

    Row {
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

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 43
            text: root.currentInfo ? root.currentInfo.shortLabel : "AI"
            color: root.foregroundColor
            font.family: "Comic Code"
            font.pixelSize: 10
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            text: root.primaryValue(root.currentProvider)
            color: text === "?" || text === "—" ? root.mutedColor : root.accentColor
            font.family: "Comic Code"
            font.pixelSize: 10
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: slotMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                aiPanel.shown = !aiPanel.shown
            else
                AiUsageState.refresh()
        }
    }

    Timer {
        interval: 4500
        running: root.providers.length > 1
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

    BarTooltip {
        panelWindow: root.panelWindow
        triggerItem: root
        below: root.tooltipBelow
        shown: slotMouse.containsMouse
        labelText: "AI PROVIDER USAGE\n\n"
            + AiUsageState.tooltip
            + "\n\nLeft-click to refresh · right-click for quota meters"
        backgroundColor: root.backgroundColor
        foregroundColor: root.foregroundColor
    }
}
