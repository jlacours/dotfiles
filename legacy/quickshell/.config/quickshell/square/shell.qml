//@ pragma UseQApplication
//@ pragma IconTheme Papirus-Dark
import Quickshell
import Quickshell.Io
import "." as Square
import "clipboard" as Clipboard
import "keybinds" as Keybinds
import "menus" as Menus

Scope {
  // Hot-reload the config when wallust re-renders the palette (inotify via
  // FileView -- .pragma library js is only evaluated at engine start, so a
  // full reload is the only way to pick up new colors).
  FileView {
    path: Quickshell.env("HOME") + "/.config/quickshell/square/wallust.js"
    watchChanges: true
    onFileChanged: Quickshell.reload(true)
  }

  Osd {}
  Square.NotificationPopups {}
  Square.NotificationCenter {}
  AiUsagePanel {}
  // Compact manual PipeWire rate selector opened from the volume block.
  VolumeMenu {}
  Bar {}
  Keybinds.KeybindOverlay {}
  Clipboard.ClipboardHistory {}
  Menus.CenterMenu {}
}
