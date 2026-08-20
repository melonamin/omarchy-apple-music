const test = require("node:test")
const assert = require("node:assert")
const M = require("../AppleMusicModel.js")

const monitor = {
  name: "DP-5",
  x: 0,
  y: 0,
  width: 5120,
  height: 2880,
  scale: 2,
  reserved: [0, 26, 0, 0]
}

test("display mode defaults to icon and keeps status compatibility", () => {
  assert.equal(M.normalizeDisplay(), "icon")
  assert.equal(M.normalizeDisplay("STATUS"), "player")
  assert.equal(M.normalizeDisplay("miniplayer"), "player")
  assert.equal(M.normalizeDisplay("player"), "player")
  assert.equal(M.normalizeDisplay("icon"), "icon")
  assert.equal(M.normalizeDisplay("album-art"), "icon")
  assert.equal(M.toggledDisplay("icon"), "player")
  assert.equal(M.toggledDisplay("player"), "icon")
})

test("click actions preserve media controls and panel access", () => {
  assert.equal(M.clickAction("icon", "left"), "togglePanel")
  assert.equal(M.clickAction("icon", "middle"), "toggleDisplay")
  assert.equal(M.clickAction("icon", "right"), "togglePanel")
  assert.equal(M.clickAction("player", "left"), "playPause")
  assert.equal(M.clickAction("player", "middle"), "toggleDisplay")
  assert.equal(M.clickAction("player", "right"), "togglePanel")
})

test("window addresses normalize to Hyprland's 0x form", () => {
  assert.equal(M.normalizeAddress("55C5D9"), "0x55c5d9")
  assert.equal(M.normalizeAddress("0xABC"), "0xabc")
  assert.equal(M.normalizeAddress(""), "")
})

test("only the dedicated or generated Apple Music app class matches", () => {
  assert.ok(M.isAppleWindow({ class: "melonamin.apple-music" }))
  assert.ok(M.isAppleWindow({ class: "chrome-music.apple.com__-Default" }))
  assert.ok(M.isAppleWindow({ initialClass: "brave-music.apple.com__-Profile_1" }))
  assert.ok(!M.isAppleWindow({ class: "chromium" }))
  assert.ok(!M.isAppleWindow({ class: "chrome-youtube.com__-Default" }))
})

test("selectWindow ignores unrelated browser windows", () => {
  const apple = { class: "melonamin.apple-music", pid: 42 }
  assert.equal(M.selectWindow([{ class: "chromium" }, apple]), apple)
  assert.equal(M.selectWindow([{ class: "chromium" }]), null)
})

test("click-away dismissal works after recovered or newly opened state", () => {
  assert.ok(!M.shouldDismissWindow(false, "0xdef", "0xabc"))
  assert.ok(!M.shouldDismissWindow(true, "abc", "0xabc"))
  assert.ok(M.shouldDismissWindow(true, "0xdef", "0xabc"))
  assert.ok(M.shouldDismissWindow(true, "", "0xabc"))
})

test("theme transitions preserve and restore dropdown focus", () => {
  assert.equal(M.focusDisposition(false, "0xdef", "0xabc", true), "keep")
  assert.equal(M.focusDisposition(true, "0xabc", "0xabc", true), "keep")
  assert.equal(M.focusDisposition(true, "", "0xabc", true), "restore")
  assert.equal(M.focusDisposition(true, "0xdef", "0xabc", true), "restore")
  assert.equal(M.focusDisposition(true, "0xdef", "0xabc", false), "dismiss")
})

test("scaled monitor geometry becomes a logical work area", () => {
  assert.deepEqual(M.monitorWorkArea(monitor), {
    x: 0,
    y: 26,
    width: 2560,
    height: 1414
  })
})

test("top-bar placement is anchored then clamped to the work area", () => {
  const rect = M.placement({
    x: 2204,
    y: 0,
    width: 27,
    height: 26,
    barPosition: "top"
  }, monitor, 960, 720, 12)
  assert.deepEqual(rect, { x: 1588, y: 38, width: 960, height: 720 })
})

test("bottom bar places the window above the reserved edge", () => {
  const bottomMonitor = { ...monitor, reserved: [0, 0, 0, 26] }
  const rect = M.placement({
    x: 1100,
    y: 0,
    width: 27,
    height: 26,
    barPosition: "bottom"
  }, bottomMonitor, 960, 720, 12)
  assert.equal(rect.y, 682)
  assert.equal(rect.x, 634)
})

test("vertical bars place inward and preserve vertical anchoring", () => {
  const leftMonitor = { ...monitor, reserved: [26, 0, 0, 0] }
  const left = M.placement({
    x: 0,
    y: 500,
    width: 26,
    height: 27,
    barPosition: "left"
  }, leftMonitor, 960, 720, 12)
  assert.deepEqual(left, { x: 38, y: 154, width: 960, height: 720 })

  const rightMonitor = { ...monitor, reserved: [0, 0, 26, 0] }
  const right = M.placement({
    x: 0,
    y: 500,
    width: 26,
    height: 27,
    barPosition: "right"
  }, rightMonitor, 960, 720, 12)
  assert.deepEqual(right, { x: 1562, y: 154, width: 960, height: 720 })
})

test("small monitors cap the app instead of placing it off-screen", () => {
  const small = {
    name: "eDP-1",
    x: 100,
    y: 50,
    width: 800,
    height: 600,
    scale: 1,
    reserved: [0, 30, 0, 0]
  }
  assert.deepEqual(M.placement({
    x: 380,
    y: 0,
    width: 24,
    height: 30,
    barPosition: "top"
  }, small, 960, 720, 12), {
    x: 112,
    y: 92,
    width: 776,
    height: 546
  })
})

test("monitor lookup prefers the named output and falls back safely", () => {
  const second = { ...monitor, name: "HDMI-A-1" }
  assert.equal(M.monitorFor([monitor, second], "HDMI-A-1"), second)
  assert.equal(M.monitorFor([monitor], "missing"), monitor)
  assert.equal(M.monitorFor([], "missing"), null)
})

test("MPRIS selection is scoped to the browser process", () => {
  const apple = { dbusName: "org.mpris.MediaPlayer2.chromium.instance4242" }
  const other = { dbusName: "org.mpris.MediaPlayer2.chromium.instance99" }
  assert.equal(M.pidFromMprisName(apple.dbusName), 4242)
  assert.equal(M.playerForPid([other, apple], 4242), apple)
  assert.equal(M.playerForPid({ 0: other, 1: apple, length: 2 }, 4242), apple)
  assert.equal(M.playerForPid([other], 4242), null)
})
