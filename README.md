# Apple Music for Omarchy

Apple Music in the Omarchy bar: click once for a full Chromium app window that behaves like a dropdown, then click away without stopping playback.

The plugin launches Apple Music in a dedicated, persistent Chromium profile and parks the window on a named Hyprland special workspace when closed. The bar switches between a compact monochrome state icon and an inline mini-player.

## Features

- Full `music.apple.com` interface in Chromium app mode, including login and browser-provided DRM support
- Dropdown-like placement against top, bottom, left, and right bars
- Pointer stays on the bar when the dropdown receives focus
- Playback continues while the window is hidden
- Current title, artist, and play state through the browser's MPRIS service
- Omarchy-style now-playing row with scrolling track and artist metadata
- Monochrome note and animated playing states that inherit the active bar theme
- Dedicated browser profile, so Apple Music has a stable session and cannot borrow metadata from unrelated tabs
- Runtime-only Hyprland rules; no edits to user configuration
- Multi-monitor-aware positioning with small-screen clamping

## Install

```bash
omarchy plugin add https://github.com/melonamin/omarchy-apple-music.git --enable
```

Omarchy ships Chromium, `jq`, Hyprland, and Quickshell, so the plugin has no additional package dependencies. If your default browser is a supported Chromium-family browser such as Google Chrome or Brave, the plugin uses that browser instead; this can improve DRM compatibility.

Apple Music playback depends on the selected browser's codec and DRM support. Plain Chromium installations without a Widevine CDM may load the site but refuse protected tracks.

## Use

- Compact mode, left or right click: open or hide Apple Music
- Mini-player mode, left click: play or pause
- Mini-player mode, right click: open or hide Apple Music
- Middle click: toggle compact icon and mini-player modes
- Scroll up/down: previous or next track
- Click another window: hide Apple Music while leaving it running

The default presentation is the fixed-width monochrome icon. Middle-click it to reveal the persistent mini-player, or set the mode explicitly:

```bash
omarchy bar set melonamin.apple-music display player
```

Restore compact mode:

```bash
omarchy bar set melonamin.apple-music display icon
```

The mini-player mirrors Omarchy's built-in now-playing row. Left-click it to play or pause, right-click it to open Apple Music, middle-click it to return to compact mode, and scroll for previous or next. The legacy `status` setting remains an alias for `player`.

## State and privacy

The browser profile lives at `$XDG_DATA_HOME/omarchy-apple-music/chromium`, falling back to `~/.local/share/omarchy-apple-music/chromium`. It contains the Apple login session and is deliberately retained when the plugin is removed.

The plugin never reads or injects JavaScript into the Apple Music page. Track metadata and controls come from Chromium's standard MPRIS interface.

To remove the plugin:

```bash
omarchy plugin remove melonamin.apple-music
hyprctl reload
```

The reload removes the runtime-only window rule. Delete the browser-profile directory separately if you also want to remove the saved Apple session.

## IPC

```bash
omarchy-shell apple-music status
omarchy-shell apple-music show
omarchy-shell apple-music hide
omarchy-shell apple-music toggle
omarchy-shell apple-music playPause
omarchy-shell apple-music next
omarchy-shell apple-music previous
```

## Tests

```bash
node --test tests/model.test.js
tests/integration.sh
```

The model suite covers window matching, scaled monitor geometry, every bar edge, small displays, and PID-scoped MPRIS selection. The integration script validates the manifest and reads live shell/compositor state without launching or closing Apple Music.

Apple and Apple Music are trademarks of Apple Inc. This project is independent and is not endorsed by or affiliated with Apple.
