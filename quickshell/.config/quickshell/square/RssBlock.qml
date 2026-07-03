import QtQuick

// Scrolling RSS news-ticker block. Shows one headline at a time with
// left/right step arrows, auto-advance, and click-to-open-in-browser.
// The marquee scrolls right-to-left when text overflows the viewport.
Item {
  id: root

  implicitHeight: Theme.barHeight
  implicitWidth: 520

  // Direction flag: true = text enters right and scrolls left.
  readonly property bool travelRightToLeft: true

  Row {
    anchors.centerIn: parent
    height: Theme.barHeight
    spacing: Theme.padSm

    // ── left arrow (‹) ──────────────────────────────────────────
    Item {
      anchors.verticalCenter: parent.verticalCenter
      implicitHeight: Theme.barHeight
      implicitWidth: arrowLeft.implicitWidth

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
        onClicked: RssState.prev()
      }
    }

    // ── scrolling viewport ──────────────────────────────────────
    Item {
      id: viewport
      anchors.verticalCenter: parent.verticalCenter
      width: 440
      height: Theme.barHeight
      clip: true

      // Scrolling headline text — positioned by NumberAnimation below.
      Text {
        id: scroller
        y: (viewport.height - implicitHeight) / 2
        text: RssState.current ? RssState.current.title : ""
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontMd
      }

      // Status placeholder: shown when no headline is available yet.
      Text {
        id: statusText
        anchors.centerIn: parent
        text: {
          if (!RssState.ready) return "loading..."
          if (RssState.items.length === 0) return "no feed"
          return ""
        }
        color: Theme.textDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontMd
        visible: text !== ""
      }

      // Click on the headline opens the article in the default browser.
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton
        onClicked: RssState.openCurrent()
      }
    }

    // ── right arrow (›) ─────────────────────────────────────────
    Item {
      anchors.verticalCenter: parent.verticalCenter
      implicitHeight: Theme.barHeight
      implicitWidth: arrowRight.implicitWidth

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
        onClicked: RssState.next()
      }
    }
  }

  // ── marquee scroll animation ──────────────────────────────────
  NumberAnimation {
    id: scrollAnim
    target: scroller
    property: "x"
    from: viewport.width
    to: -scroller.implicitWidth
    duration: Math.max(4000, scroller.implicitWidth * 18)
    loops: Animation.Infinite
  }

  function restartAnimation() {
    scrollAnim.stop()

    if (!RssState.current) {
      scroller.x = 0
      return
    }

    if (scroller.implicitWidth <= viewport.width) {
      // Text fits: centre it, no scrolling.
      scroller.x = (viewport.width - scroller.implicitWidth) / 2
    } else {
      scroller.x = viewport.width
      scrollAnim.start()
    }
  }

  Connections {
    target: RssState
    function onCurrentChanged() {
      restartAnimation()
    }
  }

  Component.onCompleted: restartAnimation()
}
