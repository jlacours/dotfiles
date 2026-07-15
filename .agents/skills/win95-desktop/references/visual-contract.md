# Win95 visual contract

## Live ownership

- Labwc session identity and bindings: `labwc/.config/labwc/`
- Window borders and canonical titlebar controls:
  `labwc/.local/share/themes/win95-{light,dark}/openbox-3/`
- GTK3/GTK4 application chrome:
  `labwc/.local/share/themes/win95-{light,dark}/gtk-{3,4}.0/`
- Runtime theme selector: `~/.local/share/themes/win95-current`
- Quickshell desktop: `quickshell/.config/quickshell/win95/`
- Shared command transport: `quickshell/.config/quickshell/scripts/qs-ipc.sh`

Do not put Labwc identity or `labwc --exit` behavior into the Hyprland square
profile. Do not import `Quickshell.Hyprland` into Win95 state.

## Canonical primitives

| Surface | Canonical source | Rule |
|---|---|---|
| Palette | `Win95Theme.qml` | Consume semantic properties; do not scatter hex colors through QML. |
| Raised/sunken edge | `BevelRect.qml` | Use square one- or two-pixel bevels; never round corners. |
| Close control | `Win95CloseButton.qml` → `win95-current/openbox-3/close-active.svg` | Render the exact 18×16 crisp SVG. Never substitute `X`, `×`, or a font icon. |
| Window titlebar | Labwc `openbox-3/themerc` | Let Labwc decorate real floating windows. Do not draw a second titlebar. |
| Taskbar | `Bar.qml` | 32px bottom bar, 1px raised top edge, compact task buttons. |
| Start surface | `StartMenu.qml` | Narrow lower-left menu with Programs cascade. |
| Search | `Win95Find.qml` | Real centered Find window, opened by Start → Find or Super+F3. |
| Notification | `NotificationPopup.qml` | Small exact popup with the same titlebar colors and canonical close SVG. |

When QML owns window-like chrome, instantiate the canonical component:

```qml
Win95CloseButton {
  onClicked: root.close()
}
```

The component resolves the runtime light/dark SVG. Edit both tracked source
variants when changing the glyph; never edit the `win95-current` runtime symlink
as if it were a third theme.

## Color and mode consistency

Light mode uses classic face `#c0c0c0`, navy highlight `#000080`, white raised
edges, and black text. Dark mode uses charcoal faces, teal highlight, light text,
and a matching solid desktop color. Every mode change must cover:

- Labwc borders and titlebar controls;
- Quickshell desktop, taskbar, Start menu, dialogs, and notifications;
- GTK named theme and Qt Windows-style palette;
- Foot/editor Wallust colors;
- desktop color and runtime mode state.

`win95-mode.sh` changes the runtime theme symlink. It must not rewrite tracked
`rc.xml` or generate theme state inside the repository.

## Interaction contract

- Super+D: open Start → Programs on the active window's monitor.
- Super+F3: open Find: Applications without stealing plain F3 from programs.
- Start/Ctrl+Escape: open the native Start popup.
- Clicking away from Start must dismiss it without a fullscreen click catcher.
- Left-clicking the desktop draws the selection marquee; right-clicking opens
  Labwc's real root menu.
- Rofi is retired. New menus use Quickshell IPC and the active Win95 profile.

## Visual verification

Capture through `~/.config/labwc/scripts/screenshot.sh full`, then inspect the
combined mixed-scale image and the relevant monitor region. Verify:

- exact border and bevel thickness;
- pixel glyph centering and crispness;
- taskbar icons and active state;
- popup placement on the active monitor;
- light/dark coverage;
- no one-pixel output gaps or full-screen transparent surfaces.
