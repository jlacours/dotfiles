pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

// Live state and controls for the default PipeWire output. Tracking the node
// keeps its audio properties subscribed so hardware keys and other mixers are
// reflected in the taskbar immediately.
Singleton {
  id: root

  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool available: sink !== null && sink.audio !== null
  readonly property bool muted: available && sink.audio.muted
  readonly property real volume: available ? sink.audio.volume : 0
  readonly property int percent: Math.round(volume * 100)

  PwObjectTracker {
    objects: root.sink === null ? [] : [root.sink]
  }

  function toggleMute(): void {
    if (available)
      sink.audio.muted = !sink.audio.muted;
  }

  function adjust(steps: real): void {
    if (!available || steps === 0)
      return;

    // Permit the same modest boost as wpctl while keeping wheel changes sane.
    sink.audio.volume = Math.max(0, Math.min(1.5, sink.audio.volume + steps * 0.05));
    if (sink.audio.muted && sink.audio.volume > 0)
      sink.audio.muted = false;
  }
}
