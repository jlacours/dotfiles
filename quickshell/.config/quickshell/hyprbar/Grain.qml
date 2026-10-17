import QtQuick 6.0

// Static, one-pixel grain. Painted only on creation or resize; no animation.
Canvas {
    id: root

    property real strength: 0.025
    opacity: strength
    antialiasing: false

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onAvailableChanged: if (available) requestPaint()

    onPaint: {
        const w = Math.ceil(width)
        const h = Math.ceil(height)
        if (w <= 0 || h <= 0)
            return
        const context = getContext("2d")
        const grain = context.createImageData(w, h)
        let seed = 17321
        for (let i = 0; i < grain.data.length; i += 4) {
            seed ^= seed << 13
            seed ^= seed >>> 17
            seed ^= seed << 5
            // Averaging two samples softens the brightest speckles.
            const tone = ((seed >>> 24) + ((seed >>> 16) & 255)) / 2
            // Establish opacity before writing RGB into Qt's pixel buffer.
            grain.data[i + 3] = 255
            grain.data[i] = tone
            grain.data[i + 1] = tone
            grain.data[i + 2] = tone
        }
        context.putImageData(grain, 0, 0, 0, 0, w, h)
    }
}
