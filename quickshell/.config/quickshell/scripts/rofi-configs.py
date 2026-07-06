#!/usr/bin/env python3

import os
import shlex
import subprocess

configs = {
    "Hyprland": os.path.expanduser("~/.config/hypr/hyprland.conf"),
    "Waybar": os.path.expanduser("~/.config/waybar/config.jsonc"),
    "Neovim": os.path.expanduser("~/.config/nvim/init.lua"),
}

menu = "\n".join(configs.keys())

qs_dmenu = os.path.expanduser("~/.config/quickshell/scripts/qs-dmenu.sh")

result = subprocess.run(
    [qs_dmenu, "-p", "Config"],
    input = menu,
    text = True,
    capture_output = True,
)

choice = result.stdout.strip()
if not choice:
    exit(0)

path = configs.get(choice)
if not path:
    exit(1)

terminal = os.environ.get("TERMINAL", "foot")
editor = os.environ.get("EDITOR", "nvim")

# Terminal editors must run inside a terminal; GUI editors (emacsclient -c,
# code, ...) are spawned directly. Decide by the editor's first token.
TUI_EDITORS = {"nvim", "vim", "vi", "nano", "micro", "neovim", "joe", "mg"}
editor_prog = editor.split()[0] if editor else ""

if editor_prog in TUI_EDITORS or editor_prog.endswith("vim"):
    argv = [terminal, "-e", "sh", "-c", f'exec {editor} "$1"', "rofi-configs", path]
else:
    argv = shlex.split(editor) + [path]

subprocess.Popen(
    argv,
    stdout = subprocess.DEVNULL,
    stderr = subprocess.DEVNULL,
)
