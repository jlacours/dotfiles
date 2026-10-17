import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick 6.0

// Live keybinding cheat sheet. keybinds.py groups `hyprctl binds -j` into
// sections; this overlay lays them out as masonry cards with keycap chords.
// IPC: qs -c keybinds ipc call keybinds toggle | open | close | search TEXT
Scope {
    id: root

    property bool shown: false
    property string screenName: ""
    property var sections: []
    property int bindCount: 0
    property string errorText: ""
    property string query: ""
    property var modFilter: []
    // Last keybinds.py output: identical output must not reassign sections,
    // since that regenerates every card on every screen.
    property string lastJson: ""

    readonly property int rowHeight: 26
    readonly property int headerHeight: 34
    readonly property int cardPadding: 8
    readonly property int gap: 14
    property bool searchFocused: false

    // Comic Code is monospaced, so one advance per size is enough to tell
    // whether a row has room for a second chord.
    TextMetrics { id: capMetrics; font.family: "Comic Code"; font.pixelSize: 11; font.weight: Font.Bold; text: "M" }
    TextMetrics { id: textMetrics; font.family: "Comic Code"; font.pixelSize: 12; text: "M" }

    function capWidth(label) {
        return Math.max(22, Math.ceil(label.length * capMetrics.advanceWidth) + 12)
    }

    function chordWidth(chord) {
        let width = 0
        for (const mod of chord.mods)
            width += capWidth(mod) + 3
        chord.groups.forEach((keys, index) => {
            const label = keys.length > 4 ? keys[0] + "…" + keys[keys.length - 1] : keys.join(" ")
            width += capWidth(label) + (index > 0 ? 16 : 0)
        })
        return width
    }

    function chordLimit(row, available) {
        if (row.chords.length < 2)
            return 1
        const text = row.text.length * textMetrics.advanceWidth
        const both = chordWidth(row.chords[0]) + chordWidth(row.chords[1]) + 22
        return text + both <= available ? 2 : 1
    }

    WallustPalette {
        id: wal
    }

    IpcHandler {
        target: "keybinds"
        function toggle(): void { root.shown ? root.hide() : root.show() }
        function open(): void { root.show() }
        function close(): void { root.hide() }
        function search(text: string): void {
            if (!root.shown)
                root.show()
            root.query = text
        }
        function state(): string {
            return (root.shown ? "shown" : "hidden") + " on " + (root.screenName || "?")
                + " · " + root.visibleRows + " rows · focus " + root.searchFocused
        }
    }

    function show() {
        const focused = Hyprland.focusedMonitor
            || Hyprland.monitors.values.find(monitor => monitor.focused)
        screenName = focused?.name || ""
        query = ""
        if (modFilter.length)
            modFilter = []
        load.exec(["python3", Qt.resolvedUrl("keybinds.py").toString().replace(/^file:\/\//, "")])
        shown = true
    }

    function hide() {
        shown = false
    }

    // Esc clears the filter, then closes. Shared by the search field and the
    // window-level catcher so Esc works even if the field never gets focus.
    function onEscape() {
        if (query !== "" || modFilter.length) {
            query = ""
            modFilter = []
        } else {
            hide()
        }
    }

    function toggleMod(name) {
        const next = modFilter.slice()
        const at = next.indexOf(name)
        if (at >= 0)
            next.splice(at, 1)
        else
            next.push(name)
        modFilter = next
    }

    function rowMatches(row, needle) {
        if (modFilter.length > 0) {
            const hit = row.chords.some(chord => modFilter.every(mod => chord.mods.includes(mod)))
            if (!hit)
                return false
        }
        if (!needle)
            return true
        if (row.text.toLowerCase().includes(needle))
            return true
        return row.chords.some(chord =>
            chord.mods.concat(chord.keys).join(" ").toLowerCase().split(" ").includes(needle))
    }

    readonly property var visibleSections: {
        const needle = query.trim().toLowerCase()
        const result = []
        for (const section of sections) {
            const titleHit = needle && section.title.toLowerCase().includes(needle) && modFilter.length === 0
            const rows = titleHit ? section.rows : section.rows.filter(row => rowMatches(row, needle))
            if (rows.length > 0)
                result.push({ title: section.title, submap: section.submap, entry: section.entry, rows: rows })
        }
        return result
    }

    readonly property int visibleRows: visibleSections.reduce((sum, section) => sum + section.rows.length, 0)

    function cardHeight(section) {
        return headerHeight + section.rows.length * rowHeight + cardPadding
    }

    // Greedy masonry: each card goes to the currently shortest column, which
    // keeps the config's reading order while balancing column heights.
    function masonry(count, list) {
        const columns = []
        const heights = []
        for (let i = 0; i < count; i++) {
            columns.push([])
            heights.push(0)
        }
        for (const section of list) {
            let target = 0
            for (let i = 1; i < count; i++)
                if (heights[i] < heights[target] - 1)
                    target = i
            columns[target].push(section)
            heights[target] += cardHeight(section) + gap
        }
        return columns
    }

    Process {
        id: load
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (text === root.lastJson)
                    return
                root.lastJson = text
                try {
                    const data = JSON.parse(text)
                    root.sections = data.sections || []
                    root.bindCount = data.count || 0
                    root.errorText = data.error || ""
                    // Quickshell's monitor list can lag a fresh start.
                    if (!root.screenName)
                        root.screenName = data.monitor || ""
                } catch (error) {
                    root.errorText = "could not read hyprctl binds"
                }
            }
        }
        onExited: exitCode => { if (exitCode !== 0) root.errorText = "keybinds.py exited " + exitCode }
    }

    component Keycap: Item {
        id: cap

        required property var theme
        property string label: ""
        property bool modifier: false
        readonly property int edge: 2
        readonly property color rim: cap.modifier
            ? cap.theme.border
            : Qt.rgba(cap.theme.muted.r, cap.theme.muted.g, cap.theme.muted.b, 0.55)

        implicitWidth: Math.max(22, capText.implicitWidth + 12)
        implicitHeight: 21

        // Lower slab peeks out under the face: a flat keycap, no rounding.
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: cap.edge
            color: cap.rim
        }

        Rectangle {
            anchors.fill: parent
            anchors.bottomMargin: cap.edge
            color: cap.modifier
                ? cap.theme.background
                : Qt.tint(cap.theme.background, Qt.rgba(cap.theme.foreground.r, cap.theme.foreground.g, cap.theme.foreground.b, 0.10))
            border.color: cap.rim
            border.width: 1

            Text {
                id: capText
                anchors.centerIn: parent
                text: cap.label
                color: cap.modifier
                    ? Qt.rgba(cap.theme.foreground.r, cap.theme.foreground.g, cap.theme.foreground.b, 0.62)
                    : cap.theme.foreground
                font.family: "Comic Code"
                font.pixelSize: 11
                font.weight: cap.modifier ? Font.Medium : Font.Bold
            }
        }
    }

    // One chord: modifier caps, then one cap per key group. Alternatives on
    // the same modifiers sit side by side: Super [← ↓ ↑ →] / [H J K L].
    component Chord: Row {
        id: chord

        required property var chordData
        required property var theme

        function capLabel(keys) {
            if (keys.length > 4)
                return keys[0] + "…" + keys[keys.length - 1]
            return keys.join(" ")
        }

        spacing: 3

        Repeater {
            model: chord.chordData.mods
            delegate: Keycap {
                required property var modelData
                theme: chord.theme
                label: modelData
                modifier: true
            }
        }

        Repeater {
            model: chord.chordData.groups

            delegate: Row {
                required property var modelData
                required property int index
                spacing: 3

                Text {
                    visible: index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -1
                    text: "/"
                    color: chord.theme.muted
                    font.family: "Comic Code"
                    font.pixelSize: 11
                }

                Keycap {
                    theme: chord.theme
                    label: chord.capLabel(modelData)
                }
            }
        }
    }

    component Card: Rectangle {
        id: card

        required property var section
        required property var theme
        required property var host

        width: parent ? parent.width : 0
        height: card.host.cardHeight(section)
        color: Qt.rgba(card.theme.surface.r, card.theme.surface.g, card.theme.surface.b, 0.55)
        border.color: card.theme.border
        border.width: 1

        Item {
            id: header
            x: 12
            width: parent.width - 24
            height: card.host.headerHeight

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.section.title.toUpperCase()
                color: card.theme.accent
                font.family: "Comic Code"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: 1.6
            }

            Row {
                visible: !!card.section.entry
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "enter"
                    color: card.theme.muted
                    font.family: "Comic Code"
                    font.pixelSize: 10
                    font.italic: true
                }

                Loader {
                    active: !!card.section.entry
                    sourceComponent: Chord { chordData: card.section.entry; theme: card.theme }
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 2
                width: parent.width
                height: 1
                color: card.theme.border
            }
        }

        Column {
            anchors.top: header.bottom
            width: parent.width

            Repeater {
                model: card.section.rows

                delegate: Rectangle {
                    id: row

                    required property var modelData
                    readonly property int limit: card.host.chordLimit(modelData, width - 24 - 10 - (modelData.hold ? 34 : 0))

                    width: parent.width
                    height: card.host.rowHeight
                    color: rowMouse.containsMouse ? card.theme.surfaceHover : "transparent"

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: chords.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.text
                        color: card.theme.foreground
                        elide: Text.ElideRight
                        // Shrink a long description a notch before eliding it.
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 11
                        font.family: "Comic Code"
                        font.pixelSize: 12
                    }

                    Row {
                        id: chords
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: 1
                        spacing: 6

                        Text {
                            visible: row.modelData.hold
                            anchors.verticalCenter: parent.verticalCenter
                            text: "hold"
                            color: card.theme.accent
                            font.family: "Comic Code"
                            font.pixelSize: 10
                            font.italic: true
                        }

                        Repeater {
                            // Two alternatives are plenty on a cheat sheet.
                            model: row.modelData.chords.slice(0, row.limit)

                            delegate: Row {
                                required property var modelData
                                required property int index
                                spacing: 6

                                Text {
                                    visible: index > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.verticalCenterOffset: -1
                                    text: "/"
                                    color: card.theme.muted
                                    font.family: "Comic Code"
                                    font.pixelSize: 11
                                }

                                Chord { chordData: modelData; theme: card.theme }
                            }
                        }

                        Text {
                            visible: row.modelData.chords.length > row.limit
                            anchors.verticalCenter: parent.verticalCenter
                            text: "+" + (row.modelData.chords.length - row.limit)
                            color: card.theme.muted
                            font.family: "Comic Code"
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: Component {
            PanelWindow {
                id: overlay

                required property var modelData
                readonly property bool active: root.shown
                    && Hyprland.monitorFor(modelData)?.name === root.screenName
                property real reveal: active ? 1 : 0

                Behavior on reveal {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }

                screen: modelData
                visible: active || reveal > 0.01
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                WlrLayershell.layer: WlrLayer.Overlay
                // Matches the "^quickshell.*" layer rule: no compositor animation (a
                // re-map mid-fade otherwise sticks at partial alpha) and blur behind.
                WlrLayershell.namespace: "quickshell-keybinds"
                WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                // Defer until the surface is mapped: focusing during the same
                // tick it becomes visible can leave no item with keyboard focus.
                onActiveChanged: if (active) Qt.callLater(() => search.forceActiveFocus())

                // Fallback key target. Exclusive focus routes every key here, so
                // something must always handle Esc or the keyboard is trapped.
                Item {
                    focus: true
                    Keys.onEscapePressed: root.onEscape()
                }

                Rectangle {
                    anchors.fill: parent
                    color: wal.background
                    opacity: 0.5 * overlay.reveal
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.hide()
                }

                Rectangle {
                    id: panel

                    readonly property int columnCount: Math.max(1, Math.floor((width - 40 + root.gap) / (400 + root.gap)))
                    readonly property var columns: root.masonry(columnCount, root.visibleSections)
                    // Sized for the unfiltered sheet so typing never makes the panel jump.
                    readonly property int contentHeight: {
                        let tallest = 0
                        for (const column of root.masonry(columnCount, root.sections)) {
                            let height = 0
                            for (const section of column)
                                height += root.cardHeight(section) + root.gap
                            tallest = Math.max(tallest, height - root.gap)
                        }
                        return tallest
                    }

                    // Sized from the screen, not the window: a hidden layer
                    // surface reports a placeholder width, and the column count
                    // flipping with it rebuilt every card on each toggle.
                    width: Math.min(overlay.modelData.width - 80, 1840)
                    height: Math.min(overlay.height - 72, Math.max(260, top.height + contentHeight + footer.height + 54))
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: Math.round(10 * (1 - overlay.reveal))
                    opacity: overlay.reveal
                    color: wal.background
                    border.color: wal.border
                    border.width: 1

                    // Swallow clicks so only the scrim closes the overlay.
                    MouseArea {
                        anchors.fill: parent
                    }

                    Rectangle {
                        width: parent.width
                        height: 2
                        color: wal.accent
                    }

                    Item {
                        id: top
                        x: 20
                        y: 14
                        width: parent.width - 40
                        height: 40

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 12

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "KEYBINDINGS"
                                color: wal.accent
                                font.family: "Comic Code"
                                font.pixelSize: 15
                                font.weight: Font.Bold
                                font.letterSpacing: 2.4
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.errorText !== ""
                                    ? root.errorText
                                    : (root.query || root.modFilter.length
                                        ? root.visibleRows + " of " + root.sections.reduce((n, s) => n + s.rows.length, 0) + " shortcuts"
                                        : root.bindCount + " binds · live from hyprctl")
                                color: wal.muted
                                font.family: "Comic Code"
                                font.pixelSize: 11
                            }
                        }

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Repeater {
                                model: ["Super", "Ctrl", "Alt", "Shift"]

                                delegate: Rectangle {
                                    id: filterChip

                                    required property var modelData
                                    readonly property bool on: root.modFilter.includes(modelData)

                                    anchors.verticalCenter: parent.verticalCenter
                                    width: filterText.implicitWidth + 18
                                    height: 26
                                    color: on ? wal.accent : (chipMouse.containsMouse ? wal.surfaceHover : "transparent")
                                    border.color: on ? wal.accent : wal.border
                                    border.width: 1

                                    Text {
                                        id: filterText
                                        anchors.centerIn: parent
                                        text: filterChip.modelData
                                        color: filterChip.on ? wal.background : wal.muted
                                        font.family: "Comic Code"
                                        font.pixelSize: 11
                                        font.weight: filterChip.on ? Font.DemiBold : Font.Normal
                                    }

                                    MouseArea {
                                        id: chipMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.toggleMod(filterChip.modelData)
                                            search.forceActiveFocus()
                                        }
                                    }
                                }
                            }

                            Item {
                                width: 8
                                height: 1
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 300
                                height: 30
                                color: Qt.rgba(wal.surface.r, wal.surface.g, wal.surface.b, 0.7)
                                border.color: search.activeFocus ? wal.accent : wal.border
                                border.width: 1

                                Text {
                                    id: glass
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "/"
                                    color: wal.accent
                                    font.family: "Comic Code"
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }

                                TextInput {
                                    id: search
                                    onActiveFocusChanged: root.searchFocused = activeFocus
                                    anchors.left: glass.right
                                    anchors.leftMargin: 8
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.query
                                    onTextEdited: root.query = text
                                    color: wal.foreground
                                    selectionColor: wal.accent
                                    selectedTextColor: wal.background
                                    font.family: "Comic Code"
                                    font.pixelSize: 13
                                    clip: true

                                    Keys.onEscapePressed: root.onEscape()

                                    Text {
                                        visible: search.text === ""
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "filter by action or key…"
                                        color: wal.muted
                                        font: search.font
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        id: body
                        anchors.top: top.bottom
                        anchors.topMargin: 14
                        anchors.bottom: footer.top
                        anchors.bottomMargin: 10
                        x: 20
                        width: parent.width - 40
                        clip: true
                        contentWidth: width
                        contentHeight: Math.max(panel.contentHeight, columnsRow.implicitHeight)
                        boundsBehavior: Flickable.StopAtBounds

                        Row {
                            id: columnsRow
                            spacing: root.gap

                            Repeater {
                                model: panel.columns

                                delegate: Column {
                                    required property var modelData
                                    width: Math.floor((body.width - root.gap * (panel.columnCount - 1)) / panel.columnCount)
                                    spacing: root.gap

                                    Repeater {
                                        model: parent.modelData
                                        delegate: Card {
                                            required property var modelData
                                            section: modelData
                                            theme: wal
                                            host: root
                                        }
                                    }
                                }
                            }
                        }

                        Text {
                            visible: root.visibleSections.length === 0 && root.sections.length > 0
                            anchors.centerIn: parent
                            text: "nothing bound to that"
                            color: wal.muted
                            font.family: "Comic Code"
                            font.pixelSize: 13
                            font.italic: true
                        }
                    }

                    Item {
                        id: footer
                        x: 20
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 10
                        width: parent.width - 40
                        height: 18

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "type to filter  ·  click a modifier to narrow  ·  esc clears, then closes"
                            color: wal.muted
                            font.family: "Comic Code"
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }
    }
}
