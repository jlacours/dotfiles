import Quickshell

// The keybinding overlay runs as its own instance (qs -c keybinds) rather than
// inside hyprbar: rebuilding its cards on the bar's much larger JS heap made
// the garbage collector stall each toggle for tens of seconds.
ShellRoot {
    KeybindOverlay {}
}
