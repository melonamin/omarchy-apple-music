(function(global) {
  "use strict"

  function number(value, fallback) {
    const parsed = Number(value)
    return Number.isFinite(parsed) ? parsed : fallback
  }

  function valueAt(source, path) {
    let value = source
    for (const part of path) {
      if (value == null) return undefined
      value = value[part]
    }
    return value
  }

  function first(source, paths, fallback) {
    for (const path of paths) {
      const value = valueAt(source, path)
      if (value !== undefined && value !== null && value !== "") return value
    }
    return fallback
  }

  function artworkUrl(item, size) {
    const template = first(item, [
      ["artworkURL"],
      ["artwork", "url"],
      ["attributes", "artwork", "url"],
      ["item", "attributes", "artwork", "url"]
    ], "")
    if (typeof template !== "string") return ""
    const pixels = Math.max(64, Math.round(number(size, 512)))
    return template
      .replaceAll("{w}", String(pixels))
      .replaceAll("{h}", String(pixels))
      .replaceAll("{f}", "webp")
  }

  function serializeItem(item, index) {
    if (!item || typeof item !== "object") return null
    const playbackDuration = number(first(item, [["playbackDuration"]], 0), 0)
    const durationMs = number(first(item, [
      ["durationInMillis"],
      ["attributes", "durationInMillis"],
      ["item", "attributes", "durationInMillis"]
    ], 0), 0)
    const duration = playbackDuration || durationMs / 1000

    return {
      index: number(index, 0),
      id: String(first(item, [["id"], ["item", "id"], ["playParams", "id"], ["attributes", "playParams", "id"]], number(index, 0))),
      title: String(first(item, [["title"], ["name"], ["attributes", "name"], ["item", "attributes", "name"]], "Unknown title")),
      artist: String(first(item, [["artistName"], ["artist"], ["attributes", "artistName"], ["item", "attributes", "artistName"]], "Apple Music")),
      album: String(first(item, [["albumName"], ["attributes", "albumName"], ["item", "attributes", "albumName"]], "")),
      artwork: artworkUrl(item, 512),
      duration: Math.max(0, duration)
    }
  }

  function queueItems(queue) {
    if (!queue) return []
    const raw = Array.isArray(queue.items) ? queue.items : []
    const position = Math.max(0, number(queue.position, 0))
    const start = position > 150 ? position - 1 : 0
    return raw.slice(start, start + 200).map(function(item, offset) {
      return serializeItem(item, start + offset)
    }).filter(Boolean)
  }

  function serializePlayer(instance) {
    if (!instance) {
      return {
        ready: false,
        playing: false,
        loading: false,
        time: 0,
        duration: 0,
        shuffle: false,
        repeat: "none",
        position: -1,
        nowPlaying: null,
        queue: []
      }
    }

    const playbackState = number(instance.playbackState, 0)
    const position = number(instance.queue && instance.queue.position, -1)
    const items = queueItems(instance.queue)
    const current = serializeItem(instance.nowPlayingItem, position)

    return {
      ready: true,
      playing: playbackState === 2,
      loading: playbackState === 1 || playbackState === 6 || playbackState === 8 || playbackState === 9,
      time: Math.max(0, number(instance.currentPlaybackTime, 0)),
      duration: Math.max(0, number(instance.currentPlaybackDuration, current ? current.duration : 0)),
      shuffle: number(instance.shuffleMode, 0) === 1,
      repeat: ["none", "one", "all"][number(instance.repeatMode, 0)] || "none",
      position,
      nowPlaying: current,
      queue: items
    }
  }

  function normalizeView(value) {
    return value === "full" ? "full" : "queue"
  }

  function formatTime(value) {
    const seconds = Math.max(0, Math.floor(number(value, 0)))
    const minutes = Math.floor(seconds / 60)
    return `${minutes}:${String(seconds % 60).padStart(2, "0")}`
  }

  const api = { artworkUrl, formatTime, normalizeView, serializeItem, serializePlayer }
  global.OmarchyAppleMusicPlayer = api
  if (typeof module !== "undefined" && module.exports) module.exports = api
})(typeof globalThis !== "undefined" ? globalThis : this)
