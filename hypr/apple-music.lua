-- Runtime-only window rules for the Apple Music shell plugin.
-- The service evaluates this file after startup and after every Hyprland
-- config reload. Nothing is written into the user's Hyprland configuration.

_G.omarchy_apple_music = _G.omarchy_apple_music or {}
local M = _G.omarchy_apple_music

function M.install(force)
  if force then M.installed = false end
  if M.installed then return "already" end
  M.installed = true

  hl.window_rule({
    match = {
      class = "^(melonamin\\.apple-music|.+-music\\.apple\\.com__.*)$",
    },
    tag = "+apple-music-dropdown",
    float = true,
    workspace = "special:melonamin-apple-music silent",
    opacity = "1.0 1.0",
    rounding = 12,
    border_size = 1,
    size = { 960, 720 },
  })

  return "installed"
end
