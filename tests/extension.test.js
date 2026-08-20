const test = require("node:test")
const assert = require("node:assert")
const theme = require("../extension/theme-model.js")

const payload = {
  revision: "theme-1",
  mode: "dark",
  colors: {
    background: "#222222",
    foreground: "#c2c2b0",
    border: "#78824b",
    accent: "#78824b",
    muted: "#666666",
    urgent: "#685742"
  }
}

test("palette validation accepts only complete six-digit hex palettes", () => {
  assert.equal(theme.validate(payload), payload)
  assert.equal(theme.validate({ ...payload, revision: "" }), null)
  assert.equal(theme.validate({ ...payload, mode: "sepia" }), null)
  assert.equal(theme.validate({
    ...payload,
    colors: { ...payload.colors, accent: "red" }
  }), null)
})

test("surface states blend predictably from theme colors", () => {
  assert.equal(theme.blend("#000000", "#ffffff", 0.04), "#0a0a0a")
  assert.equal(theme.rgba("#78824b", 0.35), "rgba(120, 130, 75, 0.35)")

  const variables = theme.variables(payload)
  assert.equal(variables["--omarchy-background"], "#222222")
  assert.equal(variables["--omarchy-elevated"], "#282828")
  assert.equal(variables["--omarchy-selected"], "rgba(120, 130, 75, 0.18)")
  assert.equal(variables["--omarchy-pressed"], "rgba(120, 130, 75, 0.22)")
  assert.equal(variables["--omarchy-selection-border"], "rgba(120, 130, 75, 0.35)")
})
