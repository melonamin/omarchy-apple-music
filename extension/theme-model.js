(function(global) {
  "use strict"

  const colorPattern = /^#[0-9a-f]{6}$/i
  const requiredColors = [
    "background",
    "foreground",
    "border",
    "accent",
    "muted",
    "urgent"
  ]

  function validColor(value) {
    return typeof value === "string" && colorPattern.test(value)
  }

  function parseColor(value) {
    if (!validColor(value)) return null
    return [
      parseInt(value.slice(1, 3), 16),
      parseInt(value.slice(3, 5), 16),
      parseInt(value.slice(5, 7), 16)
    ]
  }

  function hexByte(value) {
    return Math.max(0, Math.min(255, Math.round(value))).toString(16).padStart(2, "0")
  }

  function blend(base, overlay, amount) {
    const a = parseColor(base)
    const b = parseColor(overlay)
    if (!a || !b || !Number.isFinite(amount)) return ""
    const ratio = Math.max(0, Math.min(1, amount))
    return "#" + a.map((channel, index) => hexByte(channel + (b[index] - channel) * ratio)).join("")
  }

  function rgba(value, alpha) {
    const rgb = parseColor(value)
    if (!rgb || !Number.isFinite(alpha)) return ""
    return `rgba(${rgb.join(", ")}, ${Math.max(0, Math.min(1, alpha))})`
  }

  function rgb(value) {
    const channels = parseColor(value)
    return channels ? channels.join(", ") : ""
  }

  function validate(payload) {
    if (!payload || typeof payload !== "object") return null
    if (typeof payload.revision !== "string" || payload.revision.length === 0) return null
    if (payload.mode !== "dark" && payload.mode !== "light") return null
    if (!payload.colors || typeof payload.colors !== "object") return null
    for (const name of requiredColors) {
      if (!validColor(payload.colors[name])) return null
    }
    return payload
  }

  function variables(payload) {
    const valid = validate(payload)
    if (!valid) return null
    const colors = valid.colors
    return {
      "--omarchy-background": colors.background,
      "--omarchy-background-rgb": rgb(colors.background),
      "--omarchy-foreground": colors.foreground,
      "--omarchy-foreground-rgb": rgb(colors.foreground),
      "--omarchy-border": colors.border,
      "--omarchy-accent": colors.accent,
      "--omarchy-accent-rgb": rgb(colors.accent),
      "--omarchy-muted": colors.muted,
      "--omarchy-urgent": colors.urgent,
      "--omarchy-elevated": blend(colors.background, colors.foreground, 0.04),
      "--omarchy-hover": rgba(colors.foreground, 0.08),
      "--omarchy-selected": rgba(colors.accent, 0.18),
      "--omarchy-pressed": rgba(colors.accent, 0.22),
      "--omarchy-selection-border": rgba(colors.accent, 0.35),
      "--omarchy-divider": rgba(colors.border, 0.42),
      "--omarchy-secondary": rgba(colors.muted, 0.88),
      "--omarchy-tertiary": rgba(colors.muted, 0.62),
      "--omarchy-disabled": rgba(colors.muted, 0.38)
    }
  }

  const api = { blend, parseColor, rgba, rgb, validColor, validate, variables }
  global.OmarchyAppleMusicTheme = api
  if (typeof module !== "undefined" && module.exports) module.exports = api
})(typeof globalThis !== "undefined" ? globalThis : this)
