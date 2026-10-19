# Touchpad Manager for Omarchy

A bar widget for the [Omarchy](https://omarchy.org/) shell that lets you tune
your touchpad from a popup panel, with live preview. Built on a MacBook Pro
(Apple SPI touchpad), but it only uses standard Hyprland touchpad options, so
it works with any touchpad.

## Features

| Section | What you can change |
|---|---|
| **Profiles** | One-click presets (`macOS`, `Precise`, `Omarchy`) plus your own saved profiles (right-click a saved profile to delete it) |
| **Scrolling** | Natural scrolling on/off, scroll speed (0.1–2×) |
| **Pointer** | Pointer speed (−100% … +100%), acceleration profile (adaptive / flat) |
| **Clicking** | Tap to click, two-finger right click vs. click by area, disable while typing |
| **Gestures** | Workspace swipe on/off, 3 or 4 fingers, natural or reversed direction |
| **Per-app scrolling** | A scroll multiplier per window class (handy for terminals) |

Changes are applied immediately and persisted, so they survive a Hyprland reload and a reboot.

## Requirements

- Omarchy with the Quickshell-based shell (`omarchy plugin` available) and the
  Lua Hyprland config Omarchy ships. Developed on Hyprland 0.56.
- `python3` (standard library only).

## Install

```bash
omarchy plugin add https://github.com/FabioCuccaro/macbook_touchpad_manager.git --enable
```

`--enable` puts the widget in the bar. Without it, add the widget later with
`omarchy plugin enable fabiocuccaro.touchpad --section right`.

Click the mouse icon in the bar to open the panel. On first use the panel shows
a **Connect to Hyprland** button: it appends one line to
`~/.config/hypr/input.lua` (after saving a backup next to it):

```lua
pcall(require, "hypr.touchpad")
```

Until you connect it, changes apply live but are lost on the next Hyprland reload.

Update with `omarchy plugin update fabiocuccaro.touchpad`, remove with
`omarchy plugin remove fabiocuccaro.touchpad`.

## How it works

```
Panel.qml  ──►  bin/touchpad-ctl  ──►  ~/.config/hypr/touchpad.json   (your settings)
                      │          └──►  ~/.config/hypr/touchpad.lua    (generated Hyprland config)
                      └──►  hyprctl eval / hyprctl reload   (live apply)
```

- On the first run the settings are **seeded from the values Hyprland is using
  right now**, so enabling the plugin doesn't change how your touchpad behaves.
- Most options are pushed live with `hyprctl eval`. Gestures and per-app rules
  can only be declared in the config file, so changing them triggers a
  `hyprctl reload`.
- `touchpad.lua` is loaded with `pcall`, so a missing file never breaks your
  Hyprland config.
- Hyprland's Lua config does not support `hyprctl keyword`; that's why this
  plugin uses `hyprctl eval`.

`bin/touchpad-ctl` also works from a terminal and prints the full state as JSON:

```bash
bin/touchpad-ctl get
bin/touchpad-ctl set scroll_factor 0.6
bin/touchpad-ctl set natural_scroll true
bin/touchpad-ctl preset macOS
bin/touchpad-ctl app-set 'com.mitchellh.ghostty' 0.2
```

## Notes

- **Overlapping settings.** If your `input.lua` already sets the same options or
  declares `hl.gesture(...)` itself, remove those lines so you don't end up with
  duplicates. Settings declared later in the file win.
- **Dotfiles.** `touchpad.json` and `touchpad.lua` are per-machine. If you keep
  `~/.config` in a dotfiles repo, you probably want to ignore them.
- **Keyboard.** The panel is mouse-driven; only `Esc` (close) is bound.
- **Not included.** Drag lock and tap-and-drag, and anything driver-specific
  such as force click or haptic feedback.
- The panel language is English.

## Security

Omarchy shell plugins run unsandboxed inside the shell process. This one only
runs `touchpad-ctl` (a short, readable Python script), `hyprctl`, and edits the
files listed above. Window classes entered in the per-app section are validated
before being written to the generated Lua file.

## License

[MIT](LICENSE)
