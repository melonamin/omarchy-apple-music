(function() {
  "use strict"

  const model = globalThis.OmarchyAppleMusicPlayer
  const commandAttribute = "data-omarchy-apple-music-command"
  const stateAttribute = "data-omarchy-apple-music-state"
  const commandEvent = "omarchy-apple-music-command"
  const stateEvent = "omarchy-apple-music-state"
  const watchedEvents = [
    "nowPlayingItemDidChange",
    "playbackDurationDidChange",
    "playbackStateDidChange",
    "playbackTimeDidChange",
    "queueItemsDidChange",
    "queuePositionDidChange",
    "repeatModeDidChange",
    "shuffleModeDidChange"
  ]

  let instance = null
  let lastState = ""
  let heartbeat = 0

  function root() {
    return document.documentElement
  }

  function publish(force) {
    const element = root()
    if (!element) return
    const state = JSON.stringify(model.serializePlayer(instance))
    if (!force && state === lastState) return
    lastState = state
    element.setAttribute(stateAttribute, state)
    document.dispatchEvent(new Event(stateEvent))
  }

  function command() {
    const element = root()
    if (!element || !instance) return
    let request
    try {
      request = JSON.parse(element.getAttribute(commandAttribute) || "{}")
    } catch (_) {
      return
    }

    try {
      switch (request.name) {
      case "playPause":
        if (instance.isPlaying) instance.pause()
        else instance.play()
        break
      case "previous":
        instance.skipToPreviousItem()
        break
      case "next":
        instance.skipToNextItem()
        break
      case "seek":
        if (Number.isFinite(Number(request.value))) instance.seekToTime(Math.max(0, Number(request.value)))
        break
      case "playAt":
        if (Number.isInteger(Number(request.value))) {
          const selection = instance.changeToMediaAtIndex(Number(request.value))
          if (selection && typeof selection.catch === "function") selection.catch(function() {})
        }
        break
      case "shuffle":
        instance.shuffleMode = instance.shuffleMode === 1 ? 0 : 1
        break
      case "repeat":
        instance.repeatMode = (Number(instance.repeatMode) + 1) % 3
        break
      default:
        return
      }
      setTimeout(function() { publish(true) }, 0)
    } catch (_) {
      // Apple Music owns playback errors and exposes them in its native UI.
    }
  }

  function onPlayerEvent() {
    publish(false)
  }

  function bind(candidate) {
    if (!candidate || candidate === instance) return
    if (instance && typeof instance.removeEventListener === "function") {
      for (const name of watchedEvents) instance.removeEventListener(name, onPlayerEvent)
    }
    instance = candidate
    for (const name of watchedEvents) instance.addEventListener(name, onPlayerEvent)
    publish(true)
  }

  function discover() {
    try {
      bind(globalThis.MusicKit && globalThis.MusicKit.getInstance())
    } catch (_) {
      // MusicKit is configured asynchronously by the Apple Music application.
    }
    if (!instance) publish(false)
  }

  document.addEventListener(commandEvent, command)
  document.addEventListener("musickitloaded", discover)
  document.addEventListener("musickitconfigured", discover)
  discover()
  setInterval(discover, 1000)
  heartbeat = setInterval(function() { publish(false) }, 250)
  window.addEventListener("pagehide", function() { clearInterval(heartbeat) }, { once: true })
})()
