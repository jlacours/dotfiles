# Wallust schemes

Custom Pywal-format schemes live in `.config/wallust/colorschemes/`. The Juju
set:

- **juju-serenade** (default dark): deep green-teal ink with warm parchment
  text and candlelit amber, rose, sage, dusk-blue, and mauve accents. Text is
  14.0:1 on the background, the muted grey 5.2:1, every accent at least 7:1.
- **juju-nocturne** (dark): violet-black with warm ivory text and restrained
  peach, mint, blue, lavender, and amber accents.
- **juju-aubade** (light): cream with violet ink.
- **matrix-redpill** (dark): near-black phosphor glass where green is only the
  success color; red pill (errors, cursor), blue pill (bar accent), amber CRT,
  cyan, and violet glitch carry the rest. Every slot clears 4.6:1.

The Quickshell bar adds stationary, one-pixel grain behind its content at
2.5% opacity. Adjust `strength` in `hyprbar/Grain.qml` to tune it; zero removes
the texture. It repaints only when created or resized.

## Choosing a theme

`Super+Ctrl+;` runs `wallust-theme-menu`: custom schemes first (dark/light tag,
wallpaper thumbnail or color swatch), then every built-in Wallust theme, with
the current one marked `●`. A custom scheme also switches to
`~/Pictures/Wallpapers/<scheme>.png` when it exists; built-in themes keep the
current wallpaper. Without the menu:

```bash
wallust cs juju-serenade --skip-sequences
```

This regenerates the existing application templates. Quickshell watches the
palette, and the desktop refresh hook updates GTK. Existing terminals keep
their current ANSI colors with `--skip-sequences`; new Foot windows use the
generated colors. Omit that flag to recolor existing terminal sessions.

## Wallpapers

Every custom scheme has an abstract textured wallpaper, generated locally with
Qwen-Image 2.1 in ComfyUI and saved as `~/Pictures/Wallpapers/<scheme>.png`
(1920x1080). Its prompt and seed sit beside it in `<scheme>.prompt.txt`
(Nocturne's came from an earlier hosted model). To make or redo one:

```bash
gpu-guard run -- ~/ComfyUI/run-qwen-image-2.1.sh   # keep running in another terminal
wallust-wallpaper-gen juju-serenade prompt.txt [seed]
```

A replaced wallpaper is kept as `.<scheme>.previous.png`. Prompts name the
scheme's hex colors and one material (paper, velvet, slate, glass), keep the
center as quiet negative space, and forbid text and logos. One image takes
about four minutes on the RTX 3060.

## Designing the next scheme

Use `.config/wallust/colorschemes/juju-serenade.json` as the editable source.
Custom schemes use the Pywal format: `special.background`,
`special.foreground`, `special.cursor`, and `colors.color0` through `color15`.
The format is supported by [`wallust cs`](https://explosion-mental.codeberg.page/wallust/).

A useful brief for a model choosing colors:

> Design a cohesive sixteen-color terminal palette for Juju. Use near-black
> violet surfaces, warm ivory text, and gentle peach, mint, blue, and lavender
> accents. Preserve distinguishable red/error, green/success, amber/warning,
> blue, purple, and cyan slots. Provide normal and bright colors with enough
> hue coverage to distinguish AI providers. Keep foreground and muted text
> at least 4.5:1 against the main background, and check the lifted surfaces
> too. Output valid Pywal JSON. Keep texture in the wallpaper rather than
> adding noise behind application text.

Render into temporary output paths before changing the live theme, validate
the generated configs, save the previous palette, then apply and inspect the
live bar. The initial palette has 14.24:1 foreground contrast and 4.71:1 ANSI
grey contrast against its background.

## AI badges

Badge icons and text use the bar foreground, so the slot reads as one shade
across every Wallust palette.

Compact mode shows only the current provider's logo and value; Pi and
Hermes use their logos in the expanded stack too.

Each expanded badge uses two shared-width columns: five-hour remaining and
reset time on the left; weekly remaining and reset date on the right.
Unavailable reset times stay hidden, and the reset time has no `5h` prefix.

## Returning to a saved palette

The initial application saved the previous palette and generated files under
`~/.local/state/juju-theme/backups/`. Given a backup directory, reapply its
saved palette with:

```bash
wallust cs ~/.local/state/juju-theme/backups/<timestamp>/previous-palette \
  --format pywal --skip-sequences
```

This regenerates the current templates using the old colors. Choose the
previous wallpaper separately with the wallpaper picker's **Wallpaper only
(keep current theme)**.
The backup's `hyprpaper-conf` records its old path; `manifest.json` identifies
the saved generated files. The new colorscheme remains available for later.
