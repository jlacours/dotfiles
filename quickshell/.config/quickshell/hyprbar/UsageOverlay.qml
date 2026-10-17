import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick 6.0

// A focused-monitor usage dashboard. The companion script emits one
// credential-free JSON snapshot; its local sampler stores counters only.
Scope {
    id: root

    property bool shown: false
    property string screenName: ""
    property var snapshot: ({})
    property string errorText: ""
    property bool refreshing: false
    property string scriptPath: Qt.resolvedUrl("usage-data.py").toString().replace(/^file:\/\//, "")
    readonly property string snapshotCachePath: (Quickshell.env("XDG_CACHE_HOME")
        || ((Quickshell.env("HOME") || "") + "/.cache")) + "/ai-usage-dashboard.json"

    readonly property color panel: Qt.tint(wal.background, Qt.rgba(wal.surface.r, wal.surface.g, wal.surface.b, 0.94))
    readonly property int inset: 28

    WallustPalette { id: wal }

    IpcHandler {
        target: "usage"
        function toggle(): void { root.shown ? root.hide() : root.show() }
        function open(): void { root.show() }
        function close(): void { root.hide() }
        function state(): string {
            return (root.shown ? "shown" : "hidden") + " on " + (root.screenName || "?")
                + " · updated " + (root.snapshot.updated_at || "not yet")
        }
    }

    function show() {
        const focused = Hyprland.focusedMonitor
            || Hyprland.monitors.values.find(monitor => monitor.focused)
        screenName = focused?.name || Quickshell.screens[0]?.name || ""
        shown = true
        if (!localSampler.running)
            localSampler.exec(["python3", scriptPath, "--collect-local"])
        refresh()
    }

    function hide() { shown = false }
    function refresh() {
        if (!snapshotProcess.running) {
            refreshing = true
            snapshotProcess.exec(["python3", scriptPath])
        }
    }

    function acceptSnapshot(contents) {
        try {
            const next = JSON.parse(contents)
            if (!next || typeof next !== "object" || !Array.isArray(next.providers))
                throw new Error("unexpected snapshot shape")
            snapshot = next
            errorText = ""
        } catch (error) {
            if (!snapshot.updated_at)
                errorText = "No cached usage snapshot"
        }
    }

    function provider(id) {
        const list = snapshot.providers || []
        return list.find(item => item.id === id) || ({})
    }

    function percent(value) {
        if (value === null || value === undefined || value === "")
            return null
        const number = Number(value)
        return Number.isFinite(number) ? Math.max(0, Math.min(100, number)) : null
    }

    function money(value) {
        if (value === null || value === undefined || value === "")
            return "n/a"
        const number = Number(value)
        if (!Number.isFinite(number))
            return "n/a"
        return "$" + number.toFixed(number !== 0 && Math.abs(number) < 0.01 ? 4 : 2)
    }

    function count(value) {
        if (value === null || value === undefined || value === "")
            return "n/a"
        const number = Number(value)
        return Number.isFinite(number)
            ? String(Math.round(number)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
            : "n/a"
    }

    function resetLabel(iso, at, countdown) {
        let time = ""
        if (iso) {
            const date = new Date(iso)
            if (!isNaN(date.getTime()))
                time = String(date.getHours()).padStart(2, "0") + ":" + String(date.getMinutes()).padStart(2, "0")
        } else if (at) {
            const match = String(at).match(/(\d{1,2}:\d{2})/)
            time = match ? match[1] : String(at)
        }
        if (countdown)
            return (time ? time + "  ·  " : "") + "in " + countdown
        return time || "n/a"
    }

    function updatedLabel(value) {
        if (!value)
            return "waiting for first snapshot"
        const date = new Date(value)
        if (isNaN(date.getTime()))
            return String(value)
        return String(date.getHours()).padStart(2, "0") + ":" + String(date.getMinutes()).padStart(2, "0")
    }

    function providerTitle(id) {
        return ({
            codex: "Codex / ChatGPT",
            claude_code: "Claude",
            zai: "Z.AI / Pi",
            pi: "Pi",
            openrouter: "OpenRouter",
            local: "llama-server"
        })[id] || id
    }

    function activityLines(activity) {
        const lines = []
        if (!activity)
            return lines
        if (activity.session_input_tokens !== null && activity.session_input_tokens !== undefined
            || activity.session_output_tokens !== null && activity.session_output_tokens !== undefined) {
            const sessionTokens = Number(activity.session_input_tokens || 0) + Number(activity.session_output_tokens || 0)
            lines.push("SESSION  " + count(sessionTokens) + " tokens")
        }
        const todayTokens = Number(activity.today_input_tokens || 0) + Number(activity.today_output_tokens || 0)
        if (activity.today_input_tokens !== null && activity.today_input_tokens !== undefined
            || activity.today_output_tokens !== null && activity.today_output_tokens !== undefined
            || activity.today_cost_usd !== null && activity.today_cost_usd !== undefined) {
            let today = "TODAY"
            if (activity.today_input_tokens !== null && activity.today_input_tokens !== undefined
                || activity.today_output_tokens !== null && activity.today_output_tokens !== undefined)
                today += "  " + count(todayTokens) + " tokens"
            if (activity.today_cost_usd !== null && activity.today_cost_usd !== undefined)
                today += "  ·  ~" + money(activity.today_cost_usd)
            lines.push(today)
        }
        const weekTokens = Number(activity.seven_day_input_tokens || 0) + Number(activity.seven_day_output_tokens || 0)
        if (activity.seven_day_tokens !== null && activity.seven_day_tokens !== undefined
            || activity.seven_day_input_tokens !== null && activity.seven_day_input_tokens !== undefined
            || activity.seven_day_output_tokens !== null && activity.seven_day_output_tokens !== undefined
            || activity.seven_day_cost_usd !== null && activity.seven_day_cost_usd !== undefined) {
            let week = "ROLLING 7D"
            if (activity.seven_day_tokens !== null && activity.seven_day_tokens !== undefined)
                week += "  " + count(activity.seven_day_tokens) + " tokens"
            else if (activity.seven_day_input_tokens !== null && activity.seven_day_input_tokens !== undefined
                || activity.seven_day_output_tokens !== null && activity.seven_day_output_tokens !== undefined)
                week += "  " + count(weekTokens) + " tokens"
            if (activity.seven_day_cost_usd !== null && activity.seven_day_cost_usd !== undefined)
                week += "  ·  ~" + money(activity.seven_day_cost_usd)
            lines.push(week)
        }
        return lines
    }

    Process {
        id: snapshotProcess
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.acceptSnapshot(text)
            }
        }
        onExited: exitCode => {
            root.refreshing = false
            if (exitCode !== 0) {
                root.errorText = "Usage collector exited " + exitCode
            } else if (!root.snapshot.updated_at) {
                root.errorText = "Snapshot could not be read"
            }
        }
    }

    Process { id: localSampler }

    FileView {
        id: snapshotCache
        path: root.snapshotCachePath
        preload: true
        watchChanges: true
        printErrors: false
        onLoaded: root.acceptSnapshot(text())
        onFileChanged: reload()
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.shown
        onTriggered: root.refresh()
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: overlay
            required property var modelData

            readonly property bool active: root.shown
                && Hyprland.monitorFor(modelData)?.name === root.screenName

            screen: modelData
            visible: active
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-usage"
            WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }

            FocusScope {
                id: keyboardScope
                anchors.fill: parent
                focus: overlay.active
                Keys.onEscapePressed: root.hide()

                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 0.67)
                    opacity: overlay.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 130 } }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.hide()
                    }
                }

                Rectangle {
                    id: frame
                    anchors.centerIn: parent
                    width: Math.min(parent.width - 72, 1480)
                    height: Math.min(parent.height - 72, 900)
                    color: root.panel
                    border.color: wal.border
                    border.width: 1
                    opacity: overlay.active ? 1 : 0
                    scale: overlay.active ? 1 : 0.985
                    Behavior on opacity { NumberAnimation { duration: 130 } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 4
                        color: wal.accent
                    }

                    MouseArea { anchors.fill: parent }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 28
                        spacing: 18

                        Row {
                            width: parent.width
                            height: 62
                            spacing: 18

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - badge.width - 18
                                spacing: 5
                                Text {
                                    text: "AI USAGE"
                                    color: wal.accent
                                    font.family: "Comic Code"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    font.letterSpacing: 2.2
                                }
                                Text {
                                    text: "Capacity at a glance"
                                    color: wal.foreground
                                    font.family: "Inter"
                                    font.pixelSize: 25
                                    font.weight: Font.DemiBold
                                }
                            }

                            Rectangle {
                                id: badge
                                anchors.verticalCenter: parent.verticalCenter
                                width: badgeRow.implicitWidth + 24
                                height: 34
                                color: wal.surface
                                border.color: wal.border
                                border.width: 1

                                Row {
                                    id: badgeRow
                                    anchors.centerIn: parent
                                    spacing: 8

                                    Rectangle {
                                        id: spinner
                                        visible: root.refreshing
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 9
                                        height: 9
                                        radius: 5
                                        color: "transparent"
                                        border.color: wal.accent
                                        border.width: 2
                                        RotationAnimation {
                                            target: spinner
                                            from: 0
                                            to: 360
                                            duration: 900
                                            loops: Animation.Infinite
                                            running: root.refreshing
                                        }
                                    }

                                    Text {
                                        id: badgeText
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.refreshing
                                            ? "REFRESHING · UPDATED " + root.updatedLabel(root.snapshot.updated_at)
                                            : root.errorText
                                                ? "STALE · UPDATED " + root.updatedLabel(root.snapshot.updated_at)
                                                : "REFRESHES EVERY 60 S"
                                        color: root.errorText ? wal.accent : wal.muted
                                        font.family: "Comic Code"
                                        font.pixelSize: 10
                                        font.letterSpacing: 0.8
                                    }
                                }
                            }
                        }

                        Grid {
                            id: providersGrid
                            width: parent.width
                            columns: 3
                            spacing: 12

                            Repeater {
                                model: ["codex", "claude_code", "zai", "pi", "openrouter"]
                                delegate: ProviderCard {
                                    required property var modelData
                                    width: Math.floor((providersGrid.width - 24) / 3)
                                    height: 200
                                    providerData: root.provider(modelData)
                                    title: root.providerTitle(modelData)
                                    theme: wal
                                }
                            }
                        }

                        Row {
                            id: lowerRow
                            width: parent.width
                            height: 202
                            spacing: 12

                            Rectangle {
                                width: (lowerRow.width - 24) * 0.43
                                height: parent.height
                                color: wal.surface
                                border.color: wal.border
                                border.width: 1
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 10
                                    Row {
                                        width: parent.width
                                        Text { text: "LOCAL SAVINGS"; color: wal.accent; font.family: "Comic Code"; font.pixelSize: 11; font.letterSpacing: 1.2 }
                                        Item { width: parent.width - parent.children[0].width - localTag.width; height: 1 }
                                        Text { id: localTag; text: "ESTIMATE"; color: wal.muted; font.family: "Comic Code"; font.pixelSize: 10 }
                                    }
                                    Text {
                                        text: "5H n/a  ·  7D n/a  ·  RESETS n/a"
                                        color: wal.muted
                                        font.family: "Comic Code"
                                        font.pixelSize: 9
                                    }
                                    Row {
                                        width: parent.width
                                        spacing: 14
                                        Column {
                                            width: (parent.width - 28) / 3
                                            spacing: 5
                                            Text { text: "TODAY"; color: wal.muted; font.family: "Comic Code"; font.pixelSize: 9 }
                                            Text { text: root.money((root.snapshot.local_savings || {}).today_savings_estimate_usd); color: wal.foreground; font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold }
                                            Text { text: root.count((root.snapshot.local_savings || {}).today_tokens) + " tokens"; color: wal.muted; font.family: "Inter"; font.pixelSize: 10 }
                                        }
                                        Column {
                                            width: (parent.width - 28) / 3
                                            spacing: 5
                                            Text { text: "THIS WEEK"; color: wal.muted; font.family: "Comic Code"; font.pixelSize: 9 }
                                            Text { text: root.money((root.snapshot.local_savings || {}).week_savings_estimate_usd); color: wal.foreground; font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold }
                                            Text { text: root.count((root.snapshot.local_savings || {}).week_tokens) + " tokens"; color: wal.muted; font.family: "Inter"; font.pixelSize: 10 }
                                        }
                                        Column {
                                            width: (parent.width - 28) / 3
                                            spacing: 5
                                            Text { text: "ALL TIME"; color: wal.muted; font.family: "Comic Code"; font.pixelSize: 9 }
                                            Text { text: root.money((root.snapshot.local_savings || {}).total_savings_estimate_usd); color: wal.foreground; font.family: "Inter"; font.pixelSize: 21; font.weight: Font.DemiBold }
                                            Text { text: root.count((root.snapshot.local_savings || {}).total_tokens) + " tokens"; color: wal.muted; font.family: "Inter"; font.pixelSize: 10 }
                                        }
                                    }
                                    Text {
                                        width: parent.width
                                        wrapMode: Text.WordWrap
                                        text: (root.snapshot.local_savings || {}).estimate_note || "Waiting for local token observations."
                                        color: wal.muted
                                        font.family: "Inter"
                                        font.pixelSize: 10
                                    }
                                    Text {
                                        text: "Reference $" + Number((root.snapshot.local_savings || {}).rate_usd_per_mtok || 0.20).toFixed(2) + " / million tokens  ·  " + ((root.snapshot.local_savings || {}).model || "llama-server idle")
                                        color: wal.muted
                                        font.family: "Comic Code"
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                        width: parent.width
                                    }
                                }
                            }

                            Rectangle {
                                width: (lowerRow.width - 24) * 0.31
                                height: parent.height
                                color: wal.surface
                                border.color: wal.border
                                border.width: 1
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 13
                                    Text { text: "TRACKED CLOUD USAGE"; color: wal.accent; font.family: "Comic Code"; font.pixelSize: 11; font.letterSpacing: 1.2 }
                                    Row {
                                        width: parent.width
                                        spacing: 12
                                        Column {
                                            width: (parent.width - 12) / 2
                                            spacing: 6
                                            Text { text: "TODAY"; color: wal.muted; font.family: "Comic Code"; font.pixelSize: 9 }
                                            Text { text: root.money((root.snapshot.tracked_usage || {}).today?.cost_usd); color: wal.foreground; font.family: "Inter"; font.pixelSize: 22; font.weight: Font.DemiBold }
                                            Text { text: root.count((root.snapshot.tracked_usage || {}).today?.tokens) + " tokens"; color: wal.muted; font.family: "Inter"; font.pixelSize: 10 }
                                        }
                                        Column {
                                            width: (parent.width - 12) / 2
                                            spacing: 6
                                            Text { text: "THIS WEEK"; color: wal.muted; font.family: "Comic Code"; font.pixelSize: 9 }
                                            Text { text: root.money((root.snapshot.tracked_usage || {}).week?.cost_usd); color: wal.foreground; font.family: "Inter"; font.pixelSize: 22; font.weight: Font.DemiBold }
                                            Text { text: root.count((root.snapshot.tracked_usage || {}).week?.tokens) + " tokens"; color: wal.muted; font.family: "Inter"; font.pixelSize: 10 }
                                        }
                                    }
                                    Text { text: "OpenUsage API-equivalent estimate"; color: wal.muted; font.family: "Inter"; font.pixelSize: 10 }
                                }
                            }

                            Rectangle {
                                width: (lowerRow.width - 24) * 0.26
                                height: parent.height
                                color: wal.surface
                                border.color: wal.border
                                border.width: 1
                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 12
                                    Text { text: "WORKFLOW"; color: wal.accent; font.family: "Comic Code"; font.pixelSize: 11; font.letterSpacing: 1.2 }
                                    Text { text: countMetric((root.snapshot.workflow || {}).fallback_events) + " fallback events"; color: wal.foreground; font.family: "Inter"; font.pixelSize: 14 }
                                    Text { text: countMetric((root.snapshot.workflow || {}).reviews) + " cross-vendor reviews"; color: wal.foreground; font.family: "Inter"; font.pixelSize: 14 }
                                    Text { text: countMetric((root.snapshot.workflow || {}).findings_accepted) + " / " + countMetric((root.snapshot.workflow || {}).findings_total) + " findings accepted"; color: wal.muted; font.family: "Inter"; font.pixelSize: 11 }
                                    Item { width: 1; height: 1 }
                                    Text { text: "agent-metrics report"; color: wal.muted; font.family: "Comic Code"; font.pixelSize: 9 }
                                }
                            }
                        }

                        Row {
                            width: parent.width
                            height: 20
                            Text {
                                width: parent.width * 0.72
                                text: root.errorText ? root.errorText : "Updated " + root.updatedLabel(root.snapshot.updated_at) + "  ·  reset credits are n/a when providers do not expose a count"
                                color: root.errorText ? wal.accent : wal.muted
                                font.family: "Comic Code"
                                font.pixelSize: 9
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                width: parent.width * 0.28
                                text: "ESC  /  click outside to close"
                                color: wal.muted
                                font.family: "Comic Code"
                                font.pixelSize: 9
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }
            }
        }
    }

    component ProviderCard: Rectangle {
        id: card
        required property var providerData
        required property string title
        required property var theme
        color: theme.surface
        border.color: theme.border
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 9

            Row {
                width: parent.width
                Text { text: card.title; color: theme.foreground; font.family: "Inter"; font.pixelSize: 15; font.weight: Font.DemiBold }
                Item { width: parent.width - parent.children[0].width - resetLabel.width - 8; height: 1 }
                Text { id: resetLabel; text: "RESETS  " + (card.providerData.reset_available === null || card.providerData.reset_available === undefined ? "n/a" : card.providerData.reset_available); color: theme.muted; font.family: "Comic Code"; font.pixelSize: 9 }
            }

            WindowUsage {
                width: parent.width
                label: "5H WINDOW"
                leftPercent: card.providerData.five_hour_left
                reset: card.hostReset(card.providerData.five_hour_reset, card.providerData.five_hour_reset_at, card.providerData.five_hour_reset_in)
                theme: card.theme
            }

            WindowUsage {
                width: parent.width
                label: "7D WINDOW"
                leftPercent: card.providerData.seven_day_left
                reset: card.hostReset(card.providerData.weekly_reset, card.providerData.seven_day_reset_at, card.providerData.seven_day_reset_in)
                theme: card.theme
            }

            Repeater {
                model: card.providerData.extra_windows || []
                delegate: Row {
                    required property var modelData
                    required property int index
                    width: parent.width
                    spacing: 8
                    Text { width: 44; text: modelData.label.toUpperCase(); color: card.theme.muted; font.family: "Comic Code"; font.pixelSize: 8 }
                    Rectangle {
                        width: parent.width - 44 - extraPct.width - extraReset.width - 20
                        height: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: card.theme.border
                        Rectangle { width: parent.width * Math.max(0, Math.min(1, (modelData.left_percent || 0) / 100)); height: parent.height; color: card.theme.accent }
                    }
                    Text { id: extraPct; width: 34; text: modelData.left_percent === null ? "n/a" : Math.round(modelData.left_percent) + "%"; color: card.theme.foreground; font.family: "Comic Code"; font.pixelSize: 9; horizontalAlignment: Text.AlignRight }
                    Text { id: extraReset; width: 72; text: modelData.reset_in ? "in " + modelData.reset_in : "n/a"; color: card.theme.muted; font.family: "Comic Code"; font.pixelSize: 8; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                }
            }

            Text {
                visible: card.providerData.remaining !== null && card.providerData.remaining !== undefined
                text: "Credit balance  " + root.money(card.providerData.remaining)
                color: theme.muted
                font.family: "Inter"
                font.pixelSize: 10
            }
            Text {
                visible: card.providerData.total_tokens !== null && card.providerData.total_tokens !== undefined
                text: root.count(card.providerData.total_tokens) + " all-time tokens"
                color: theme.muted
                font.family: "Inter"
                font.pixelSize: 10
            }

            Repeater {
                model: root.activityLines(card.providerData.activity)
                delegate: Text {
                    required property var modelData
                    width: parent.width
                    text: modelData
                    color: theme.muted
                    font.family: "Comic Code"
                    font.pixelSize: 8
                    elide: Text.ElideRight
                }
            }
        }

        function hostReset(iso, at, countdown) { return root.resetLabel(iso, at, countdown) }
    }

    component WindowUsage: Column {
        id: windowUsage
        required property string label
        required property var leftPercent
        required property string reset
        required property var theme
        spacing: 4

        Row {
            width: parent.width
            Text { text: windowUsage.label; color: windowUsage.theme.muted; font.family: "Comic Code"; font.pixelSize: 9; font.letterSpacing: 0.8 }
            Item { width: parent.width - parent.children[0].width - percentText.width - 8; height: 1 }
            Text { id: percentText; text: root.percent(windowUsage.leftPercent) === null ? "n/a" : Math.round(root.percent(windowUsage.leftPercent)) + "% left"; color: windowUsage.theme.foreground; font.family: "Comic Code"; font.pixelSize: 10 }
        }
        Rectangle {
            width: parent.width
            height: 5
            color: windowUsage.theme.border
            Rectangle {
                width: parent.width * (root.percent(windowUsage.leftPercent) === null ? 0 : root.percent(windowUsage.leftPercent) / 100)
                height: parent.height
                color: windowUsage.theme.accent
                opacity: 0.9
            }
        }
        Text {
            text: "resets " + windowUsage.reset
            color: windowUsage.theme.muted
            font.family: "Comic Code"
            font.pixelSize: 9
            elide: Text.ElideRight
            width: parent.width
        }
    }

    function countMetric(value) {
        if (value === null || value === undefined || value === "")
            return "n/a"
        const number = Number(value)
        return Number.isFinite(number) ? Math.round(number).toLocaleString() : "n/a"
    }
}
