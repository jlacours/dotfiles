import QtQuick

// Continuous news ticker. All headlines are joined into one long string and
// scrolled seamlessly right-to-left, like a TV news crawl, so a headline is
// never cut off mid-read. The ‹ › arrows snap to the previous / next headline;
// clicking the strip opens whichever headline is currently at the left edge of
// the viewport. Hovering the text pauses the crawl. Mirrors the bar's brutalist
// Theme tokens.
Item {
  id: root

  // Width is dictated by the caller (anchored left/right in the bar), so only
  // fix the height; the scrolling viewport fills whatever horizontal space is
  // allocated between the side arrows.
  height: Theme.barHeight

  readonly property string sep: "  ·  "
  readonly property real scrollSpeed: 1.4   // px per ~16ms tick (~88px/s)
  readonly property int viewportW: viewport.width

  // Segments derived from RssState.items: {title, link, w, startX}. Widths are
  // measured by `meter` (same font as the strip) so arrow/click hit-testing
  // matches what's on screen.
  property var segments: []
  property real totalWidth: 0
  property real offset: 0          // bounded to [0, totalWidth); strip.x = -offset
  // Index of the headline currently at the viewport's left edge (drives arrows
  // and click-to-open). Pure binding over offset, recomputed as the crawl moves.
  property int index: root.indexAt(root.offset)

  // Flat model for the strip Repeater: segments repeated enough times to cover
  // the viewport through the wrap-around. Each entry: {title, startX, loop}.
  property var stripModel: []

  function rebuild() {
    const items = RssState.items || []
    const segs = []
    let x = 0
    for (let i = 0; i < items.length; i++) {
      const it = items[i]
      const title = (it && it.title) ? it.title : ""
      if (!title) continue
      const label = title + root.sep
      meter.text = label
      const w = meter.implicitWidth
      segs.push({ title: label, link: (it.link || ""), w: w, startX: x })
      x += w
    }
    root.segments = segs
    root.totalWidth = x
    root.rebuildStripModel()
    if (root.offset >= root.totalWidth) root.offset = 0
  }

  function rebuildStripModel() {
    const segs = root.segments
    if (segs.length === 0 || root.totalWidth <= 0) {
      root.stripModel = []
      return
    }
    const copies = Math.max(2, Math.ceil(root.viewportW / root.totalWidth) + 1)
    const m = []
    for (let loop = 0; loop < copies; loop++) {
      for (let i = 0; i < segs.length; i++) {
        m.push({ title: segs[i].title, startX: segs[i].startX, loop: loop })
      }
    }
    root.stripModel = m
  }

  // Which segment contains a given virtual position (already in [0, totalWidth))?
  function indexAt(pos) {
    const segs = root.segments
    if (segs.length === 0 || root.totalWidth <= 0) return 0
    let p = pos
    if (p < 0) p = 0
    if (p >= root.totalWidth) p = root.totalWidth - 1
    for (let i = 0; i < segs.length; i++) {
      const s = segs[i]
      if (p >= s.startX && p < s.startX + s.w) return i
    }
    return segs.length - 1
  }

  function snapTo(i) {
    const segs = root.segments
    if (segs.length === 0) return
    const target = ((i % segs.length) + segs.length) % segs.length
    // Align that headline's start to the viewport's left edge.
    root.offset = segs[target].startX
  }

  function openCurrent() {
    const segs = root.segments
    if (root.index >= 0 && root.index < segs.length && segs[root.index].link) {
      RssState.openLink(segs[root.index].link)
    }
  }

  // ── layout: ‹ arrow pinned left | filling viewport | › arrow pinned right
  // The viewport stretches to whatever width the bar allocates to the block,
  // so the ticker expands horizontally with the window.

  // ‹ previous headline
  Item {
    id: arrowLeftBox
    anchors {
      left: parent.left
      verticalCenter: parent.verticalCenter
    }
    implicitHeight: Theme.barHeight
    implicitWidth: arrowLeft.implicitWidth + Theme.padXs

    Text {
      id: arrowLeft
      anchors.centerIn: parent
      text: "\uf0d9"
      font.family: Theme.iconFamily
      font.pixelSize: Theme.fontMd
      color: arrowLeftMouse.containsMouse ? Theme.accent : Theme.textDim
    }

    MouseArea {
      id: arrowLeftMouse
      anchors.fill: parent
      anchors.margins: -Theme.padXs
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: root.snapTo(root.index - 1)
    }
  }

  Item {
    id: viewport
    anchors {
      left: arrowLeftBox.right
      leftMargin: Theme.padSm
      right: arrowRightBox.left
      rightMargin: Theme.padSm
      verticalCenter: parent.verticalCenter
    }
    height: Theme.barHeight
    clip: true
    onWidthChanged: root.rebuildStripModel()

    // The moving strip. Rendered as segments × enough copies to keep the
    // viewport filled across the seamless wrap-around.
    Item {
      id: strip
      height: Theme.barHeight
      x: -root.offset

      Repeater {
        model: root.stripModel
        Text {
          x: modelData.startX + modelData.loop * root.totalWidth
          y: (viewport.height - implicitHeight) / 2
          text: modelData.title
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontMd
        }
      }
    }

    // loading / empty placeholders
    Text {
      anchors.centerIn: parent
      text: !RssState.ready ? "loading..." : (root.segments.length === 0 ? "no feed" : "")
      color: Theme.textDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontMd
      visible: text !== ""
    }

    // Click opens the headline at the left edge; hover pauses the crawl.
    MouseArea {
      id: viewportHover
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openCurrent()
    }
  }

  // › next headline
  Item {
    id: arrowRightBox
    anchors {
      right: parent.right
      verticalCenter: parent.verticalCenter
    }
    implicitHeight: Theme.barHeight
    implicitWidth: arrowRight.implicitWidth + Theme.padXs

    Text {
      id: arrowRight
      anchors.centerIn: parent
      text: "\uf0da"
      font.family: Theme.iconFamily
      font.pixelSize: Theme.fontMd
      color: arrowRightMouse.containsMouse ? Theme.accent : Theme.textDim
    }

    MouseArea {
      id: arrowRightMouse
      anchors.fill: parent
      anchors.margins: -Theme.padXs
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      onClicked: root.snapTo(root.index + 1)
    }
  }

  // Hidden text used only to measure headline widths (same font as the strip).
  Text {
    id: meter
    visible: false
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontMd
  }

  // Continuous crawl. A Timer (not a NumberAnimation) drives offset so arrow
  // snaps can reposition freely without fighting an animation that owns the
  // property. Pauses while the pointer is over the text.
  Timer {
    id: scroller
    interval: 16
    repeat: true
    running: root.totalWidth > 0 && !viewportHover.containsMouse
    onTriggered: {
      if (root.totalWidth > 0)
        root.offset = (root.offset + root.scrollSpeed) % root.totalWidth
    }
  }

  // Rebuild segments whenever the feed items change.
  Connections {
    target: RssState
    function onItemsChanged() { root.rebuild() }
  }

  Component.onCompleted: root.rebuild()
}
