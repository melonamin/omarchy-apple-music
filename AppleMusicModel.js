var PLUGIN_ID = "melonamin.apple-music"
var WINDOW_CLASS = "melonamin.apple-music"
var SPECIAL_WORKSPACE = "special:melonamin-apple-music"
var DISPLAY_MODES = ["icon", "player"]

function number(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function normalizeDisplay(value) {
  var mode = String(value || "icon").toLowerCase()
  if (mode === "status" || mode === "mini" || mode === "miniplayer") return "player"
  return DISPLAY_MODES.indexOf(mode) === -1 ? "icon" : mode
}

function toggledDisplay(value) {
  return normalizeDisplay(value) === "player" ? "icon" : "player"
}

function clickAction(display, button) {
  var mode = normalizeDisplay(display)
  var mouseButton = String(button || "left").toLowerCase()
  if (mouseButton === "middle") return "toggleDisplay"
  if (mouseButton === "right") return "togglePanel"
  return mode === "player" ? "playPause" : "togglePanel"
}

function normalizeAddress(value) {
  var address = String(value || "").trim().toLowerCase()
  if (!address) return ""
  return address.indexOf("0x") === 0 ? address : "0x" + address
}

function eventParts(event, count) {
  try {
    if (event && event.parse) return event.parse(count)
  } catch (error) {
  }
  return String(event && event.data ? event.data : "").split(",")
}

function isAppleWindow(client) {
  if (!client) return false
  var current = String(client.class || "").toLowerCase()
  var initial = String(client.initialClass || "").toLowerCase()
  if (current === WINDOW_CLASS || initial === WINDOW_CLASS) return true
  return current.indexOf("music.apple.com__") !== -1
    || initial.indexOf("music.apple.com__") !== -1
}

function selectWindow(clients) {
  var list = Array.isArray(clients) ? clients : []
  for (var i = 0; i < list.length; i++) {
    if (isAppleWindow(list[i])) return list[i]
  }
  return null
}

function shouldDismissWindow(opened, focusedAddress, windowAddress) {
  return focusDisposition(opened, focusedAddress, windowAddress, false) === "dismiss"
}

function focusDisposition(opened, focusedAddress, windowAddress, preserveForTheme) {
  var window = normalizeAddress(windowAddress)
  if (!opened || !window) return "keep"
  if (normalizeAddress(focusedAddress) === window) return "keep"
  return preserveForTheme ? "restore" : "dismiss"
}

function monitorFor(monitors, name) {
  var list = Array.isArray(monitors) ? monitors : []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i] && list[i].name || "") === String(name || "")) return list[i]
  }
  return list.length > 0 ? list[0] : null
}

function monitorWorkArea(monitor) {
  if (!monitor) return null
  var scale = Math.max(0.1, number(monitor.scale, 1))
  var reserved = Array.isArray(monitor.reserved) ? monitor.reserved : [0, 0, 0, 0]
  var left = Math.max(0, number(reserved[0], 0))
  var top = Math.max(0, number(reserved[1], 0))
  var right = Math.max(0, number(reserved[2], 0))
  var bottom = Math.max(0, number(reserved[3], 0))
  var x = number(monitor.x, 0) + left
  var y = number(monitor.y, 0) + top
  var width = Math.max(1, number(monitor.width, 1280) / scale - left - right)
  var height = Math.max(1, number(monitor.height, 720) / scale - top - bottom)
  return { x: x, y: y, width: width, height: height }
}

function clamp(value, minimum, maximum) {
  if (maximum < minimum) return minimum
  return Math.max(minimum, Math.min(value, maximum))
}

function placement(anchor, monitor, desiredWidth, desiredHeight, gap) {
  var work = monitorWorkArea(monitor)
  if (!work) return null

  var margin = Math.max(0, number(gap, 12))
  var width = Math.round(Math.min(Math.max(320, number(desiredWidth, 960)), Math.max(320, work.width - margin * 2)))
  var height = Math.round(Math.min(Math.max(320, number(desiredHeight, 720)), Math.max(320, work.height - margin * 2)))
  width = Math.min(width, Math.round(work.width))
  height = Math.min(height, Math.round(work.height))

  var localX = number(anchor && anchor.x, work.width / 2)
  var localY = number(anchor && anchor.y, 0)
  var anchorWidth = Math.max(1, number(anchor && anchor.width, 1))
  var anchorHeight = Math.max(1, number(anchor && anchor.height, 1))
  var edge = String(anchor && anchor.barPosition || "top")
  var x = number(monitor.x, 0) + localX + anchorWidth / 2 - width / 2
  var y = work.y + margin

  if (edge === "bottom") {
    y = work.y + work.height - height - margin
  } else if (edge === "left") {
    x = work.x + margin
    y = number(monitor.y, 0) + localY + anchorHeight / 2 - height / 2
  } else if (edge === "right") {
    x = work.x + work.width - width - margin
    y = number(monitor.y, 0) + localY + anchorHeight / 2 - height / 2
  }

  x = Math.round(clamp(x, work.x + margin, work.x + work.width - width - margin))
  y = Math.round(clamp(y, work.y + margin, work.y + work.height - height - margin))
  return { x: x, y: y, width: width, height: height }
}

function pidFromMprisName(value) {
  var match = String(value || "").match(/\.instance(\d+)$/i)
  return match ? parseInt(match[1], 10) : 0
}

function playerForPid(players, pid) {
  var wanted = parseInt(pid, 10) || 0
  if (!wanted) return null
  var list = players && typeof players.length === "number" ? players : []
  for (var i = 0; i < list.length; i++) {
    if (pidFromMprisName(list[i] && list[i].dbusName) === wanted) return list[i]
  }
  return null
}

if (typeof module !== "undefined") {
  module.exports = {
    PLUGIN_ID: PLUGIN_ID,
    WINDOW_CLASS: WINDOW_CLASS,
    SPECIAL_WORKSPACE: SPECIAL_WORKSPACE,
    DISPLAY_MODES: DISPLAY_MODES,
    normalizeDisplay: normalizeDisplay,
    toggledDisplay: toggledDisplay,
    clickAction: clickAction,
    normalizeAddress: normalizeAddress,
    eventParts: eventParts,
    isAppleWindow: isAppleWindow,
    selectWindow: selectWindow,
    shouldDismissWindow: shouldDismissWindow,
    focusDisposition: focusDisposition,
    monitorFor: monitorFor,
    monitorWorkArea: monitorWorkArea,
    placement: placement,
    pidFromMprisName: pidFromMprisName,
    playerForPid: playerForPid
  }
}
