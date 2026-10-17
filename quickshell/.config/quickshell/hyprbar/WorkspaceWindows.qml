import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick 6.0
import Qt5Compat.GraphicalEffects

// Include occupied workspaces as well as visible/focused empty workspaces.
Row {
    id: root
    required property var panelWindow
    spacing: 2
    readonly property var workspaces: Hyprland.workspaces.values
        .filter(workspace => workspace.active || workspace.focused
            || (workspace.id > 0 && workspace.toplevels.values.length > 0))
        .sort((a, b) => a.id - b.id)
    readonly property var symbols: ({ shell: "›_", terminal: "▣", nvim: "N", vim: "V",
        emacs: "E", emacsclient: "E", claude: "✳", codex: "⬡", hermes: "H",
        pi: "π", herdr: "▥" })
    readonly property var logos: ({ claude: "ai-claude.svg", codex: "ai-codex.svg",
        hermes: "ai-hermes.svg", pi: "ai-pi.svg",
        herdr: "app-herdr.svg" })

    function themeIcon(name) {
        return name && Quickshell.hasThemeIcon(name) ? Quickshell.iconPath(name) : ""
    }

    Repeater {
        // ScriptModel diffs the filtered list, so a focus change reuses the
        // existing badges instead of recreating every chip and tooltip.
        model: ScriptModel {
            values: root.workspaces
        }
        delegate: Rectangle {
            id: workspaceGroup
            required property var modelData
            implicitWidth: badgeContents.implicitWidth + 12
            implicitHeight: 22
            color: modelData.focused ? root.panelWindow.accent : root.panelWindow.surface
            readonly property color ink: modelData.focused
                ? root.panelWindow.background : root.panelWindow.foreground

            Row {
                id: badgeContents
                anchors.centerIn: parent
                height: 22
                spacing: 1

                BarChip {
                    id: workspaceId
                    panelWindow: root.panelWindow
                    implicitWidth: Math.max(10, idLabel.implicitWidth)
                    color: "transparent"
                    tooltipText: "Workspace " + workspaceGroup.modelData.id
                        + (workspaceGroup.modelData.name !== String(workspaceGroup.modelData.id)
                            ? " · " + workspaceGroup.modelData.name : "")
                    onClicked: Hyprland.dispatch(Hyprland.usingLua
                        ? "hl.dsp.focus({ workspace = " + workspaceGroup.modelData.id + " })"
                        : "workspace " + workspaceGroup.modelData.id)
                    Text {
                        id: idLabel
                        anchors.centerIn: parent
                        text: workspaceGroup.modelData.id
                        color: workspaceGroup.ink
                        font.family: "Comic Code"
                        font.pixelSize: 12
                        font.weight: workspaceGroup.modelData.focused ? Font.DemiBold : Font.Medium
                    }
                }

                Repeater {
                    model: workspaceGroup.modelData.toplevels
                    delegate: BarChip {
                        id: cell
                        required property var modelData
                        readonly property var app: WindowApps.apps[String(modelData.lastIpcObject.pid)]
                        readonly property string appId: modelData.lastIpcObject.class || modelData.wayland?.appId || ""
                        readonly property bool isHelium: ["helium", "helium-browser"].includes(appId.toLowerCase())
                        readonly property bool focused: modelData.activated
                        readonly property string icon: app
                            ? (root.logos[app.kind] ? Qt.resolvedUrl(root.logos[app.kind]).toString()
                                : root.themeIcon(app.kind === "emacsclient" ? "emacs" : app.kind))
                            : (isHelium ? Qt.resolvedUrl("app-helium.svg").toString() : root.themeIcon(appId))
                        panelWindow: root.panelWindow
                        implicitWidth: 15
                        color: "transparent"
                        // Keep individual window tooltips and clicks within the shared badge.
                        tooltipText: (app?.label || appId || "Window") + "\n" + modelData.title
                        onClicked: {
                            const address = modelData.address
                            if (/^(0x)?[0-9a-fA-F]+$/.test(address))
                                Hyprland.dispatch(Hyprland.usingLua
                                    ? "hl.dsp.focus({ window = 'address:" + address + "' })"
                                    : "focuswindow address:" + address)
                        }
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 11
                            height: 2
                            visible: cell.focused
                            color: workspaceGroup.modelData.focused ? cell.backgroundColor : cell.accentColor
                        }
                        IconImage {
                            id: appIcon
                            anchors.centerIn: parent
                            implicitSize: 11
                            source: cell.icon
                            visible: cell.icon.length > 0
                            layer.enabled: cell.icon.length > 0
                            layer.effect: ColorOverlay {
                                color: workspaceGroup.ink
                            }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: cell.app ? (root.symbols[cell.app.kind] || "▣") : "◇"
                            visible: cell.icon.length === 0 || appIcon.status === Image.Error
                            color: workspaceGroup.ink
                            font.family: "Comic Code"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
