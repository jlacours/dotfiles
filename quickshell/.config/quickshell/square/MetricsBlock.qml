import QtQuick

// Compact vitals readout, styled like the AI-usage block: each metric is a
// small bold muted label followed by its value. The CPU governor (GovBlock)
// sits right after CPU.
//   "CPU 12% 40°  GOV PERF  MEM 38%  GPU 26% 45°  VRM 91%"
Item {
  id: root

  implicitHeight: Theme.barHeight
  implicitWidth: row.implicitWidth

  // Values are left-padded so each readout keeps a constant width and
  // never pushes its neighbours around.
  function pct(v) {
    return (v >= 0 ? String(Math.round(v)) : "--").padStart(3) + "%"
  }

  function deg(v) {
    return v >= 0 ? " " + String(Math.round(v)).padStart(2) + "°" : ""
  }

  // Metric segments rendered after the governor.
  readonly property var rest: [
    { tag: "MEM", text: pct(MetricsState.memPercent) },
    { tag: "GPU", text: pct(MetricsState.gpuUsage) + deg(MetricsState.gpuTemp) },
    { tag: "VRM", text: pct(MetricsState.vramPercent) }
  ]

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.padMd

    // CPU — usage + temperature.
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Theme.padSm

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "CPU"
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSm
        font.bold: true
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.pct(MetricsState.cpuUsage) + root.deg(MetricsState.cpuTemp)
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontMd
        font.bold: true
      }
    }

    // Governor — wedged in right after CPU.
    GovBlock {
      anchors.verticalCenter: parent.verticalCenter
    }

    // MEM / GPU / VRM.
    Repeater {
      model: root.rest

      Row {
        id: seg
        required property var modelData
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.padSm

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: seg.modelData.tag
          color: Theme.textMuted
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontSm
          font.bold: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: seg.modelData.text
          color: Theme.text
          font.family: Theme.fontFamily
          font.pixelSize: Theme.fontMd
          font.bold: true
        }
      }
    }
  }
}
