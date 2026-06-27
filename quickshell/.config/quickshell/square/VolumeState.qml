pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Singleton {
  id: root

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var sinkAudio: sink ? sink.audio : null

  property int volume: volumeFromSink()
  property bool muted: sinkAudio ? sinkAudio.muted : false
  property bool ready: false

  function clampVolume(value) {
    return Math.max(0, Math.min(100, Math.round(value)))
  }

  function volumeFromSink() {
    if (!sinkAudio) return 0
    return clampVolume(sinkAudio.volume * 100)
  }

  function setVolume(val) {
    if (!sinkAudio) return
    sinkAudio.volume = clampVolume(val) / 100
  }

  function toggleMute() {
    if (!sinkAudio) return
    sinkAudio.muted = !sinkAudio.muted
  }

  function syncFromSink() {
    root.volume = volumeFromSink()
    root.muted = sinkAudio ? sinkAudio.muted : false
  }

  readonly property string icon: {
    if (muted) return "󰖁"
    if (volume >= 66) return "󰕾"
    if (volume >= 33) return "󰖀"
    if (volume > 0) return "󰕿"
    return "󰝟"
  }

  // Glyph for the active output *device* (not the volume level). device.bus,
  // node.name, node.nick and node.description are present on the pipewire node
  // props; form_factor/icon_name are not, so detect from bus + name regex.
  // Reactive: rebinds on sink change and on properties change.
  readonly property string deviceIcon: {
    if (!sink) return "󰓃"                       // speaker (fallback)
    const p = sink.properties || ({})
    const bus = String(p["device.bus"] || "").toLowerCase()
    const name = String(p["node.name"] || "").toLowerCase()
    const desc = String((p["node.description"] || "") + " " + (p["node.nick"] || "")).toLowerCase()
    const hay = name + " " + desc

    const headset = /head ?set|kraken|arctis|hyperx|steelseries|jabra|gaming|quadcast/.test(hay)
    const headphone = headset
      || /head ?phone|sennheiser|beyerdynamic|\bdt[ _-]?\d{3}\b|\bath[ _-]|\bhd[ _-]?\d{2,3}\b|earphone|earbud|airpod|galaxy buds|\bw[hf][ _-]?\d/.test(hay)

    if (bus === "bluetooth" || name.indexOf("bluez") !== -1)
      return headphone ? "󰋎" : "󰥟"            // bt headset : bt-audio
    if (/hdmi|displayport/.test(hay))
      return "󰍹"                                // monitor / digital display out
    if (headset) return "󰋎"                      // headset (with mic)
    if (headphone) return "󰋋"                    // headphones
    return "󰓃"                                   // analog / internal / usb speakers
  }

  onSinkChanged: syncFromSink()
  onSinkAudioChanged: syncFromSink()
  Component.onCompleted: {
    syncFromSink()
    ready = true
  }

  PwObjectTracker {
    objects: root.sink ? [root.sink] : []
  }

  Connections {
    target: root.sinkAudio

    function onMutedChanged() {
      root.muted = root.sinkAudio ? root.sinkAudio.muted : false
      if (root.ready) {
        OsdState.show(root.muted ? "󰖁" : root.icon,
          root.muted ? "MUTED" : "VOLUME " + root.volume + "%")
      }
    }

    function onVolumesChanged() {
      root.volume = root.volumeFromSink()
      if (root.ready && !root.muted) {
        OsdState.show(root.icon, "VOLUME " + root.volume + "%")
      }
    }
  }
}
