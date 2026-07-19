#!/usr/bin/env python3
"""Show the active Labwc keybindings through the Win95 Quickshell menu."""

from pathlib import Path
import os
import subprocess
import xml.etree.ElementTree as ET


MODIFIERS = {
    "W": "Super",
    "S": "Shift",
    "C": "Ctrl",
    "A": "Alt",
}


def friendly_key(key: str) -> str:
    return "+".join(MODIFIERS.get(part, part) for part in key.split("-"))


def action_label(action: ET.Element) -> str:
    name = action.get("name", "Action")
    if name == "Execute":
        return action.get("command", "Execute")
    details = []
    for key, value in action.attrib.items():
        if key != "name":
            details.append(f"{key}={value}")
    return name + (f" ({', '.join(details)})" if details else "")


def main() -> None:
    home = Path.home()
    root = ET.parse(home / ".config/labwc/rc.xml").getroot()
    rows = []
    for bind in root.findall("./keyboard/keybind"):
        key = bind.get("key")
        action = bind.find("action")
        if not key or action is None:
            continue
        rows.append(f"{friendly_key(key):<24} {action_label(action)}")

    menu = home / ".config/quickshell/scripts/qs-dmenu.sh"
    env = os.environ.copy()
    subprocess.run(
        [str(menu), "-i", "-no-custom", "-p", "Labwc keybindings"],
        input="\n".join(rows) + "\n",
        text=True,
        check=False,
        env=env,
    )


if __name__ == "__main__":
    main()
