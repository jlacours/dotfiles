import os
import runpy
import subprocess

from libqtile import bar, layout, qtile, widget, hook
from libqtile.config import (
    Click,
    Drag,
    DropDown,
    Group,
    Key,
    KeyChord,
    Match,
    ScratchPad,
    Screen,
)
from libqtile.lazy import lazy
from libqtile.backend.wayland.inputs import InputConfig

colors = runpy.run_path(
    os.path.join(os.path.dirname(__file__), "colors.py")
)["colors"]

bar_colors = {
    "background": colors["bg"],
    "foreground": colors["fg"],
    "muted": colors["c8"],
    "accent": colors["c5"],
    "critical": colors["c1"],
}

# The native 1080p output needs a slimmer bar than the scaled 4K output.
BAR_HEIGHT_1080P = 22
BAR_HEIGHT_4K = 28

mod = "mod4"
home = os.path.expanduser("~")
terminal = "foot"
webbrowser = "helium-browser"
alt_webbrowser = "librewolf"
scripts = f"{home}/.config/qtile/scripts"
idle_inhibitor = f"{home}/.config/session/idle-inhibit.sh"


@hook.subscribe.startup_once
def autostart():
    # Output layout first. Scale 1.5 keeps DP-2's logical grid integral under
    # wlroots; 1.6 leaves a partial logical pixel that corrupts the right edge.
    subprocess.Popen([
        "wlr-randr",
        "--output", "DP-2", "--mode", "3840x2160@60", "--pos", "0,0", "--scale", "1.5",
        "--output", "HDMI-A-1", "--mode", "1920x1080@74.973", "--pos", "2560,360",
        "--output", "DP-1", "--mode", "1920x1080@100", "--pos", "0,-1080",
    ])
    # Games ask XWayland for its primary output instead of respecting the
    # monitor they were launched on. XWayland starts lazily, so retry briefly.
    subprocess.Popen([
        "sh", "-c",
        "for _ in 1 2 3 4 5; do "
        "xrandr --output HDMI-A-1 --primary >/dev/null 2>&1 && exit 0; sleep 1; "
        "done",
    ])
    # Restart portals and the polkit agent so nothing retains a backend or
    # Wayland socket from a previous compositor session.
    subprocess.Popen([f"{home}/.config/session/reset-display-services.sh"])
    # hyprpaper no longer runs outside Hyprland (hyprtoolkit builds bail on
    # qtile's xdg_wm_base version), so restore the last wallust wallpaper with
    # swaybg; wallpaper-apply.sh restarts it on theme changes.
    subprocess.Popen([
        "sh", "-c",
        'wp=$(cat "$HOME/.cache/wallust-current-wallpaper" 2>/dev/null); '
        '[ -f "$wp" ] && exec swaybg -m fill -i "$wp"',
    ])
    subprocess.Popen(["mako"])
    subprocess.Popen(["wl-paste", "--watch", "cliphist", "store"])
    subprocess.Popen(["nm-applet", "--indicator"])
    # Keep logs: silent inhibit-lock leaks are undebuggable otherwise.
    subprocess.Popen([
        "sh", "-c",
        f'hypridle -c "{home}/.config/qtile/hypridle.conf" '
        f'>"{home}/.cache/hypridle.log" 2>&1',
    ])


def get_governor():
    try:
        with open("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor") as f:
            gov = f.read().strip()
        return "PERF" if gov == "performance" else "PWR"
    except:
        return "?"


keys = [
    # Navigation (Vim + arrows). mod+space stays unbound: it belongs to the
    # XKB layout toggle (grp:win_space_toggle).
    Key([mod], "h", lazy.layout.left(), desc="Focus left"),
    Key([mod], "l", lazy.layout.right(), desc="Focus right"),
    Key([mod], "j", lazy.layout.down(), desc="Focus down"),
    Key([mod], "k", lazy.layout.up(), desc="Focus up"),
    Key([mod], "Left", lazy.layout.left(), desc="Focus left"),
    Key([mod], "Right", lazy.layout.right(), desc="Focus right"),
    Key([mod], "Down", lazy.layout.down(), desc="Focus down"),
    Key([mod], "Up", lazy.layout.up(), desc="Focus up"),
    Key([mod], "u", lazy.group.focus_back(), desc="Focus last window"),
    Key([mod], "Tab", lazy.group.next_window(), desc="Next window"),
    Key([mod, "shift"], "Tab", lazy.group.prev_window(), desc="Previous window"),

    # Moving windows
    Key([mod, "shift"], "h", lazy.layout.shuffle_left(), desc="Move window left"),
    Key([mod, "shift"], "l", lazy.layout.shuffle_right(), desc="Move window right"),
    Key([mod, "shift"], "j", lazy.layout.shuffle_down(), desc="Move window down"),
    Key([mod, "shift"], "k", lazy.layout.shuffle_up(), desc="Move window up"),
    Key([mod, "shift"], "Left", lazy.layout.shuffle_left(), desc="Move window left"),
    Key([mod, "shift"], "Right", lazy.layout.shuffle_right(), desc="Move window right"),
    Key([mod, "shift"], "Down", lazy.layout.shuffle_down(), desc="Move window down"),
    Key([mod, "shift"], "Up", lazy.layout.shuffle_up(), desc="Move window up"),

    # Resizing
    Key([mod, "control"], "h", lazy.layout.grow_left(), desc="Grow window left"),
    Key([mod, "control"], "l", lazy.layout.grow_right(), desc="Grow window right"),
    Key([mod, "control"], "j", lazy.layout.grow_down(), desc="Grow window down"),
    Key([mod, "control"], "k", lazy.layout.grow_up(), desc="Grow window up"),
    Key([mod], "comma", lazy.layout.shrink_main(), desc="Shrink main pane"),
    Key([mod], "period", lazy.layout.grow_main(), desc="Grow main pane"),
    Key([mod, "shift"], "n", lazy.layout.normalize(), desc="Reset window sizes"),
    KeyChord(
        [mod], "r",
        [
            Key([], "h", lazy.layout.shrink_main(), desc="Shrink main"),
            Key([], "l", lazy.layout.grow_main(), desc="Grow main"),
            Key([], "j", lazy.layout.shrink(), desc="Shrink window"),
            Key([], "k", lazy.layout.grow(), desc="Grow window"),
            Key([], "Left", lazy.layout.shrink_main(), desc="Shrink main"),
            Key([], "Right", lazy.layout.grow_main(), desc="Grow main"),
            Key([], "Down", lazy.layout.shrink(), desc="Shrink window"),
            Key([], "Up", lazy.layout.grow(), desc="Grow window"),
            Key([], "n", lazy.layout.normalize(), desc="Reset window sizes"),
        ],
        mode=True,
        name="resize",
        desc="Resize mode (Escape exits)",
    ),

    # Layout
    Key([mod], "o", lazy.layout.flip(), desc="Flip main pane side"),
    Key([mod], "backslash", lazy.next_layout(), desc="Cycle layout"),

    # Launchers
    Key([mod], "Return", lazy.spawn(terminal), desc="Open terminal"),
    Key([mod, "shift"], "Return", lazy.group["scratchpad"].dropdown_toggle("term"), desc="Dropdown terminal"),
    Key([mod], "equal", lazy.group["scratchpad"].dropdown_toggle("term"), desc="Dropdown terminal"),
    Key([mod], "minus", lazy.group["scratchpad"].dropdown_toggle("calcurse"), desc="Calcurse scratchpad"),
    Key([mod], "d", lazy.spawn("fuzzel"), desc="App launcher"),
    Key([mod], "e", lazy.spawn(f"{terminal} -e ranger"), desc="File manager"),
    Key([mod, "shift"], "e", lazy.spawn("pcmanfm"), desc="GUI file manager"),
    Key([mod], "a", lazy.spawn("emacsclient -c"), desc="Emacs"),
    Key([mod, "shift"], "a", lazy.spawn(f"{terminal} --app-id=nvim -e nvim"), desc="Neovim"),
    Key([mod], "w", lazy.spawn(webbrowser), desc="Web browser"),
    Key([mod, "shift"], "w", lazy.spawn(alt_webbrowser), desc="Alt. web browser"),
    Key([mod], "b", lazy.spawn(f"{home}/.local/bin/fuzzel-apps"), desc="Favorite apps menu"),
    Key([mod], "s", lazy.spawn(f"{home}/.local/bin/fuzzel-tools"), desc="Tools menu"),
    Key([mod], "F1", lazy.spawn(f"{scripts}/keybinds-menu.sh"), desc="Show keybindings"),
    # Root-menu stand-in: the win95 quickshell desktop synthesizes this key on
    # desktop right-click.
    Key([mod, "shift"], "F12", lazy.spawn("fuzzel"), desc="Desktop menu"),

    # Window actions
    Key([mod], "q", lazy.window.kill(), desc="Kill active window"),
    Key([mod], "f", lazy.window.toggle_fullscreen(), desc="Toggle fullscreen"),
    Key([mod, "shift"], "f", lazy.window.toggle_floating(), desc="Toggle floating"),
    Key([mod, "shift"], "c", lazy.window.center(), desc="Center floating window"),

    # Bars and session
    Key([mod], "slash", lazy.hide_show_bar("all"), desc="Toggle bars"),
    Key([mod, "shift"], "slash", lazy.reload_config(), desc="Reload config"),
    Key([mod, "control"], "r", lazy.reload_config(), desc="Reload config"),
    Key([mod, "control"], "q", lazy.shutdown(), desc="Shutdown Qtile"),
    Key([mod, "shift"], "q", lazy.spawn(f"{scripts}/power-menu.sh"), desc="Power menu"),
    Key([mod], "F12", lazy.spawn("sh -c 'loginctl lock-session; sleep 1; wlopm --off \"*\"'"), desc="Lock and screens off"),

    # Theme
    Key([mod, "shift"], "semicolon", lazy.spawn(f"{home}/.local/bin/wallust-random-light"), desc="Random light theme"),

    # Notifications (mako)
    Key([mod], "n", lazy.spawn("makoctl dismiss --all"), desc="Dismiss notifications"),

    # Audio
    Key([mod], "m", lazy.spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), desc="Toggle mute"),
    Key([mod, "shift"], "m", lazy.spawn(f"{terminal} --app-id=pulsemixer -e pulsemixer"), desc="Pulsemixer"),
    Key([mod, "control"], "m", lazy.spawn(f"{home}/.local/bin/cycle-sink"), desc="Cycle audio output"),
    Key([], "XF86AudioRaiseVolume", lazy.spawn("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 1%+"), desc="Volume up"),
    Key([], "XF86AudioLowerVolume", lazy.spawn("wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-"), desc="Volume down"),
    Key([], "XF86AudioMute", lazy.spawn("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), desc="Toggle mute"),

    # Screenshots
    Key([], "Print", lazy.spawn(f"{scripts}/screenshot.sh full"), desc="Screenshot screen"),
    Key(["shift"], "Print", lazy.spawn(f"{scripts}/screenshot.sh region-save"), desc="Screenshot region"),
    Key(["control"], "Print", lazy.spawn(f"{scripts}/screenshot.sh region-copy"), desc="Screenshot region to clipboard"),

    # Utilities
    Key([mod], "v", lazy.spawn(f"{scripts}/cliphist-menu.sh"), desc="Clipboard history"),
    Key([mod], "i", lazy.spawn(f"{idle_inhibitor} toggle"), desc="Toggle idle inhibitor"),
    Key([mod, "control"], "o", lazy.spawn(f"{home}/.local/bin/tts-selection"), desc="Read selection aloud"),
    Key([mod], "semicolon", lazy.spawn(f"{home}/Projects/repos/llm-corrector-tui/bin/llm-corrector-field"), desc="LLM-correct focused field"),
    Key([mod], "c", lazy.spawn(f"{home}/.local/bin/voice-input"), desc="Voice input (oneshot)"),

    # System controls
    Key([], "F13", lazy.spawn(f"{idle_inhibitor} toggle"), desc="Toggle idle inhibitor"),
    Key([], "F14", lazy.spawn(f"{home}/.local/bin/hypridle-suspend toggle"), desc="Toggle suspend inhibitor"),
    # Discord controls (global shortcuts)
    Key([], "F21", lazy.spawn("wtype -M ctrl -M shift m"), desc="Discord mute"),
    Key([], "F20", lazy.spawn("wtype -M ctrl -M shift d"), desc="Discord deafen"),
]

for vt in range(1, 8):
    keys.append(
        Key(
            ["control", "mod1"],
            f"f{vt}",
            lazy.core.change_vt(vt).when(func=lambda: qtile.core.name == "wayland"),
            desc=f"Switch to VT{vt}",
        )
    )


groups = []
for i in "12":
    groups.append(Group(i))
for i in "34":
    groups.append(Group(i, layouts=[
        layout.MonadTall(
            border_width=2,
            border_focus=colors["c2"],
            border_normal=colors["c0"],
            margin=10,
            single_border_width=2,
            single_margin=10,
            new_client_position="before_current",
        ),
        layout.Max(),
    ]))
for i in "56":
    groups.append(Group(i))

for g in groups:
    keys.extend(
        [
            Key(
                [mod],
                g.name,
                lazy.group[g.name].toscreen(),
                desc=f"Switch to group {g.name}",
            ),
            Key(
                [mod, "shift"],
                g.name,
                lazy.window.togroup(g.name, switch_group=True),
                desc=f"Switch to & move focused window to group {g.name}",
            ),
        ]
    )

keys.extend([
    Key([mod], "z", lazy.screen.prev_group(skip_empty=True), desc="Previous busy group"),
    Key([mod], "x", lazy.screen.next_group(skip_empty=True), desc="Next busy group"),
    Key([mod, "shift"], "z", lazy.screen.prev_group(skip_empty=False), desc="Previous group"),
    Key([mod, "shift"], "x", lazy.screen.next_group(skip_empty=False), desc="Next group"),
])

groups.append(
    ScratchPad(
        "scratchpad",
        [
            DropDown(
                "term",
                f"{terminal} --app-id=scratchpad -o colors-dark.alpha=0.9 -e zsh",
                width=0.32, height=0.4, x=0.34, y=0.05,
                opacity=1.0,
                on_focus_lost_hide=False,
            ),
            DropDown(
                "calcurse",
                f"{terminal} --app-id=calcurse -e calcurse-sync",
                width=0.4, height=0.5, x=0.3, y=0.25,
                opacity=1.0,
                on_focus_lost_hide=False,
            ),
        ],
    )
)

layouts = [
    layout.MonadTall(
        border_width=2,
        border_focus=colors["c2"],
        border_normal=colors["c0"],
        margin=10,
        single_border_width=0,
        single_margin=0,
        max_ratio=0.75,
        min_ratio=0.25,
        new_client_position="before_current",
    ),
    layout.Max(),
]

widget_defaults = dict(
    font="Comic Code",
    fontsize=12,
    padding=5,
    foreground=bar_colors["foreground"],
)
extension_defaults = widget_defaults.copy()


def init_widgets_list():
    """Minimal bar: workspaces, layout, window title, and clock."""
    return [
        widget.Spacer(length=4),
        widget.GroupBox(
            highlight_method="line",
            active=bar_colors["foreground"],
            inactive=bar_colors["muted"],
            this_current_screen_border=bar_colors["accent"],
            other_current_screen_border=bar_colors["muted"],
            urgent_text=bar_colors["critical"],
            hide_unused=False,
            rounded=False,
            spacing=2,
            padding_x=6,
            margin_y=2,
        ),
        widget.Spacer(length=4),
        widget.CurrentLayout(
            fmt="{}",
            padding=7,
            foreground=bar_colors["accent"],
            mouse_callbacks={"Button1": lazy.next_layout()},
        ),
        widget.WindowName(
            empty_group_string="Desktop",
            padding=6,
            foreground=bar_colors["foreground"],
        ),
        widget.Clock(
            format="%a %d %b  %H:%M",
            padding=8,
            foreground=bar_colors["accent"],
        ),
        widget.Spacer(length=4),
    ]


def init_secondary_widgets_list():
    """Create fresh widget instances for the second output."""
    return init_widgets_list()

screens = [
    # Screen 0: right native-resolution 1080p monitor.
    Screen(
        top=bar.Bar(
            init_widgets_list(),
            size=BAR_HEIGHT_1080P,
            background=bar_colors["background"],
        ),
    ),
    # Screen 1: left 4K monitor at 1.5x scale.
    Screen(
        top=bar.Bar(
            init_secondary_widgets_list(),
            size=BAR_HEIGHT_4K,
            background=bar_colors["background"],
        ),
    ),
]

# Drag floating layouts.
mouse = [
    Drag([mod], "Button1", lazy.window.set_position_floating(), start=lazy.window.get_position()),
    Drag([mod], "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()),
    Click([mod], "Button2", lazy.window.bring_to_front()),
]

dgroups_key_binder = None
dgroups_app_rules = []  # type: list
follow_mouse_focus = True
bring_front_click = False
floats_kept_above = True
cursor_warp = True
floating_layout = layout.Floating(
    float_rules=[
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),  # gitk
        Match(wm_class="makebranch"),  # gitk
        Match(wm_class="maketag"),  # gitk
        Match(wm_class="ssh-askpass"),  # ssh-askpass
        Match(title="branchdialog"),  # gitk
        Match(title="pinentry"),  # GPG key password entry
        Match(wm_class="scratchpad"),
        Match(wm_class="calcurse"),
        Match(wm_class="pulsemixer"),
        Match(wm_class="journal"),
        Match(wm_class="zenity"),
        Match(wm_class="xdg-desktop-portal-gtk"),
        Match(title="llm-corrector"),
        Match(wm_class="zen", title="Picture-in-Picture"),
        Match(title="DayZ Launcher"),
    ]
)
auto_fullscreen = True
focus_on_window_activation = "smart"
focus_previous_on_window_remove = False
reconfigure_screens = True

auto_minimize = True

# numlock-on has no InputConfig equivalent; Hyprland's numlock_by_default is
# approximated by numlockx-style tools if ever needed.
wl_input_rules = {
    "type:keyboard": InputConfig(
        kb_layout="us,ca",
        kb_variant=",multix",
        kb_options="caps:escape,grp:win_space_toggle,fkeys:basic_13-24",
    )
}

wl_xcursor_theme = "S1mpleDark"
wl_xcursor_size = 24

wmname = "LG3D"
