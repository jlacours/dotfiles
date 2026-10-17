#!/usr/bin/env python3
"""Group the live Hyprland bindings into sections for the keybind overlay.

`hyprctl binds -j` is the only source of bindings. Section titles come from the
short `-- Heading` comments in the Lua config: each description literal is
filed under the heading above it. Bindings that match no literal fall back to
keyword guesses, so a hyprland.conf setup still renders sensibly.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

MODS = ((64, "Super"), (4, "Ctrl"), (8, "Alt"), (1, "Shift"))
DIRECTIONS = ("left", "down", "up", "right")
KEY_LABELS = {
    "return": "Enter", "escape": "Esc", "tab": "Tab", "space": "Space",
    "left": "←", "right": "→", "up": "↑", "down": "↓",
    "bracketleft": "[", "bracketright": "]", "comma": ",", "period": ".",
    "slash": "/", "backslash": "\\", "semicolon": ";", "minus": "-",
    "equal": "=", "grave": "`", "apostrophe": "'",
    "xf86audioraisevolume": "Vol+", "xf86audiolowervolume": "Vol−",
    "xf86audiomute": "Mute", "xf86audioplay": "Play", "xf86audionext": "Next",
    "xf86audioprev": "Prev", "print": "Print",
    "mouse:272": "LMB", "mouse:273": "RMB", "mouse:274": "MMB",
    "mouse_down": "Wheel↓", "mouse_up": "Wheel↑",
}
FALLBACK_SECTIONS = (
    ("Workspaces", ("workspace", "scratchpad")),
    ("Focus", ("focus",)),
    ("Moving windows", ("move", "swap", "promote")),
    ("Layout", ("layout", "column", "stack", "group", "tab")),
    ("Audio", ("volume", "mute", "audio")),
    ("Launchers", ("open", "launcher", "browser", "terminal", "manager")),
    ("Session", ("lock", "power", "idle", "suspend", "screen")),
)


def key_label(key):
    if not key or key == "catchall":
        return "any key"
    label = KEY_LABELS.get(key.lower())
    if label:
        return label
    return key.upper() if len(key) == 1 else key


def modifiers(mask):
    return [name for bit, name in MODS if mask & bit]


def heading(comment_lines):
    """Return a short title from a comment block, or None for prose."""
    first = re.split(r"\.(\s|$)", " ".join(comment_lines).strip())[0].strip()
    if not first or "," in first or len(first.split()) > 4:
        return None
    return first


def lua_sections(config_dir):
    """Map description literals (and literal prefixes) to their heading."""
    literals, prefixes = {}, {}
    queue, seen = [config_dir / "hyprland.lua"], set()
    while queue:
        path = queue.pop(0)
        if path in seen:
            continue
        seen.add(path)
        try:
            lines = path.read_text().splitlines()
        except OSError:
            continue
        for module in re.findall(r'require\(?\s*["\']([\w./-]+)["\']', "\n".join(lines)):
            queue.append(config_dir / (module.replace(".", "/") + ".lua"))
        section, block, previous_blank = None, [], True
        for line in lines:
            stripped = line.strip()
            if line.startswith("-- ") or line == "--":
                if previous_blank or block:
                    block.append(line[2:].strip())
                continue
            if block:
                section = heading(block) or section
                block = []
            previous_blank = not stripped
            if not section:
                continue
            for literal in re.findall(r'"((?:[^"\\]|\\.)*)"', line):
                target = prefixes if re.search(rf'"{re.escape(literal)}"\s*\.\.', line) else literals
                target.setdefault(literal, section)
    return literals, prefixes


def section_for(bind, literals, prefixes):
    description = bind["description"]
    if description in literals:
        return literals[description]
    for prefix in sorted(prefixes, key=len, reverse=True):
        if len(prefix) >= 4 and description.startswith(prefix):
            return prefixes[prefix]
    lowered = description.lower()
    for title, words in FALLBACK_SECTIONS:
        if any(word in lowered for word in words):
            return title
    return "Other"


def strip_variant(description):
    """Split "Focus left (Vim)" into ("Focus left", "Vim")."""
    match = re.fullmatch(r"(.*\S)\s+\(([^()]+)\)", description)
    return (match.group(1), match.group(2)) if match else (description, None)


def merge_rows(binds):
    """Collapse equivalent bindings into rows of alternative chords."""
    rows, by_text = [], {}
    descriptions = {b["description"] for b in binds}

    for bind in binds:
        text, variant = strip_variant(bind["description"])
        if variant is None or text not in descriptions:
            text, variant = bind["description"], None
        chord = {"mods": modifiers(bind["modmask"]), "keys": [key_label(bind["key"])]}
        row = by_text.get(text)
        if row is None:
            row = {"text": text, "chords": [], "release": bool(bind["release"]),
                   "hold": False, "mouse": bool(bind["mouse"])}
            by_text[text] = row
            rows.append(row)
        if chord not in row["chords"]:
            row["chords"].append(chord)

    rows = collapse(rows, direction_key, direction_text)
    rows = collapse(rows, number_key, number_text)
    return [group_chords(row) for row in join_same_chord(rows)]


def direction_key(row):
    words = row["text"].split()
    hits = [i for i, word in enumerate(words) if word.lower() in DIRECTIONS]
    if len(hits) != 1:
        return None
    i = hits[0]
    return (" ".join(words[:i] + ["{}"] + words[i + 1:]), words[i].lower())


def direction_text(template, members):
    # The keycaps already show the directions, so the text drops them.
    order = sorted(members, key=lambda m: DIRECTIONS.index(m[0]))
    text = " ".join(template.replace("{}", "").split())
    return text or template.replace("{}", "direction"), [m for _, m in order]


def number_key(row):
    match = re.fullmatch(r"(.*\D)(\d+)", row["text"])
    if not match:
        return None
    return (match.group(1) + "{}", int(match.group(2)))


def number_text(template, members):
    order = sorted(members, key=lambda m: m[0])
    first, last = order[0][0], order[-1][0]
    return template.replace("{}", f"{first}–{last}"), [m for _, m in order]


def collapse(rows, key_of, text_of):
    """Fold rows that differ only by a direction word or trailing number.

    The folded row keeps one chord per original chord slot, listing the keys
    in order, e.g. Super + [← ↓ ↑ →] or Super + [H J K L].
    """
    groups, order = {}, []
    for row in rows:
        found = key_of(row)
        if found is None:
            order.append(("row", row))
            continue
        template, value = found
        shape = tuple(tuple(chord["mods"]) for chord in row["chords"])
        group_id = (template, shape)
        if group_id not in groups:
            groups[group_id] = []
            order.append(("group", group_id))
        groups[group_id].append((value, row))

    merged = []
    for kind, item in order:
        if kind == "row":
            merged.append(item)
            continue
        members = groups[item]
        if len(members) < 2:
            merged.append(members[0][1])
            continue
        text, ordered = text_of(item[0], members)
        chords = []
        for slot, chord in enumerate(ordered[0]["chords"]):
            chords.append({"mods": chord["mods"],
                           "keys": [m["chords"][slot]["keys"][0] for m in ordered]})
        merged.append({"text": text, "chords": chords,
                       "release": ordered[0]["release"], "hold": False,
                       "mouse": ordered[0]["mouse"]})
    return merged


def join_same_chord(rows):
    """Press/release pairs on one chord share a row: "Start / stop voice input"."""
    merged, seen = [], {}
    for row in rows:
        signature = json.dumps(row["chords"])
        first = seen.get(signature)
        if first is None:
            seen[signature] = row
            merged.append(row)
            continue
        a, b = first["text"].split(), row["text"].split()
        shared = 0
        while shared < min(len(a), len(b)) - 1 and a[-1 - shared] == b[-1 - shared]:
            shared += 1
        if shared:
            first["text"] = " ".join(a[:-shared]) + " / " + " ".join(b[:-shared]).lower() \
                + " " + " ".join(a[-shared:])
        else:
            first["text"] = f"{first['text']} / {row['text'][0].lower()}{row['text'][1:]}"
        first["hold"] = first["hold"] or row["release"] != first["release"]
    return merged


def group_chords(row):
    """Alternatives with the same modifiers share their caps: Super + [←↓↑→] / [HJKL]."""
    chords = []
    for chord in row["chords"]:
        same = next((c for c in chords if c["mods"] == chord["mods"]), None)
        if same is None:
            chords.append({"mods": chord["mods"], "groups": [chord["keys"]]})
        elif chord["keys"] not in same["groups"]:
            same["groups"].append(chord["keys"])
    return {"text": row["text"], "chords": chords, "hold": row["hold"], "mouse": row["mouse"]}


def focused_monitor():
    try:
        raw = subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True,
                             text=True, check=True, timeout=5).stdout
        return next((m["name"] for m in json.loads(raw) if m.get("focused")), "")
    except (OSError, subprocess.SubprocessError, ValueError):
        return ""


def main():
    try:
        raw = subprocess.run(["hyprctl", "binds", "-j"], capture_output=True,
                             text=True, check=True, timeout=5).stdout
        binds = json.loads(raw)
    except (OSError, subprocess.SubprocessError, ValueError) as error:
        json.dump({"error": str(error), "sections": []}, sys.stdout)
        return

    literals, prefixes = lua_sections(Path.home() / ".config" / "hypr")
    submaps = {b["submap"] for b in binds if b.get("submap")}
    sections, by_name = [], {}
    for bind in binds:
        submap = bind.get("submap") or ""
        entering = re.fullmatch(r"Enter (\w+) mode", bind["description"])
        if entering and entering.group(1).lower() in submaps:
            submap = entering.group(1).lower()
        name = f"{submap.capitalize()} mode" if submap else section_for(bind, literals, prefixes)
        section = by_name.get(name)
        if section is None:
            section = {"title": name, "submap": submap, "entry": None, "rows": []}
            by_name[name] = section
            sections.append(section)
        if entering and submap:
            section["entry"] = {"mods": modifiers(bind["modmask"]), "groups": [[key_label(bind["key"])]]}
        else:
            section["rows"].append(bind)

    for section in sections:
        section["rows"] = merge_rows(section["rows"])
    sections = [s for s in sections if s["rows"]]

    json.dump({"count": len(binds), "monitor": focused_monitor(), "sections": sections},
              sys.stdout, ensure_ascii=False)


if __name__ == "__main__":
    main()
