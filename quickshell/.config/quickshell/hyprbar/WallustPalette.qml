import Quickshell
import Quickshell.Io
import QtQuick 6.0

Scope {
    id: root

    property color background: "#111318"
    property color surface: "#1a1d24"
    property color surfaceHover: "#252934"
    property color border: "#252934"
    property color foreground: "#e7e9ee"
    property color muted: "#858b98"
    property color accent: "#a9b7ff"

    readonly property string palettePath:
        (Quickshell.env("HOME") || "") + "/.cache/wallust/quickshell-hyprbar.json"

    function hexToRgb(hex) {
        const clean = String(hex).replace("#", "")
        if (clean.length !== 6)
            return { r: 0, g: 0, b: 0 }

        return {
            r: parseInt(clean.slice(0, 2), 16),
            g: parseInt(clean.slice(2, 4), 16),
            b: parseInt(clean.slice(4, 6), 16)
        }
    }

    function luminance(hex) {
        const color = hexToRgb(hex)
        return (0.299 * color.r + 0.587 * color.g + 0.114 * color.b) / 255
    }

    function distance(first, second) {
        const a = hexToRgb(first)
        const b = hexToRgb(second)
        return Math.abs(a.r - b.r) + Math.abs(a.g - b.g) + Math.abs(a.b - b.b)
    }

    function applyPalette(contents) {
        if (!contents)
            return

        try {
            const colors = JSON.parse(contents)
            const nextBackground = colors.background
            const light = luminance(nextBackground) > 0.5
            const filteredSurface = light ? colors.surfaceLight : colors.surfaceDark
            const filteredBorder = light ? colors.borderLight : colors.borderDark
            const filteredMuted = light ? colors.mutedLight : colors.mutedDark
            const safeSurface = distance(colors.color0, nextBackground) < 55
                ? filteredSurface
                : colors.color0
            const safeBorder = distance(colors.color8, safeSurface) < 90
                ? filteredBorder
                : colors.color8
            const safeMuted = distance(colors.color8, nextBackground) < 130
                ? filteredMuted
                : colors.color8

            root.background = nextBackground
            root.surface = safeSurface
            root.surfaceHover = light ? colors.hoverLight : colors.hoverDark
            root.border = safeBorder
            root.foreground = colors.foreground
            root.muted = safeMuted
            root.accent = colors.color4
        } catch (error) {
            console.warn("Could not parse Wallust hyprbar palette:", error)
        }
    }

    FileView {
        id: paletteFile

        path: root.palettePath
        preload: true
        watchChanges: true
        printErrors: false

        onLoaded: root.applyPalette(text())
        onFileChanged: reload()
    }
}
