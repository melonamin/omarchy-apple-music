(function() {
  "use strict"

  const model = globalThis.OmarchyAppleMusicTheme
  const themeUrl = chrome.runtime.getURL("theme.json")
  const spectrumUrl = chrome.runtime.getURL("spectrum.json")
  const activePollInterval = 100
  const idlePollInterval = 1000
  const activePollDuration = 3000
  const spectrumBandCount = 32
  const spectrumPollInterval = 42
  const suppressedLinks = new WeakMap()
  const commandAttribute = "data-omarchy-apple-music-command"
  const stateAttribute = "data-omarchy-apple-music-state"
  const commandEvent = "omarchy-apple-music-command"
  const stateEvent = "omarchy-apple-music-state"
  let revision = ""
  let playerState = {
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
  let panelView = "queue"
  let queueSignature = ""
  let seeking = false
  let activePollUntil = 0
  let pollTimer = 0
  let spectrumPollTimer = 0
  let spectrumFrame = 0
  let spectrumLiveAt = 0
  let spectrumTargets = Array(spectrumBandCount).fill(0)
  let spectrumLevels = Array(spectrumBandCount).fill(0)
  let spectrumPeaks = Array(spectrumBandCount).fill(0)
  let activatingAnchor = null

  function webLink(anchor) {
    const href = anchor && anchor.getAttribute ? anchor.getAttribute("href") : ""
    if (!href) return false
    try {
      const target = new URL(href, window.location.href)
      return target.protocol === "https:" || target.protocol === "http:"
    } catch (_) {
      return false
    }
  }

  function suppressLink(anchor) {
    const current = anchor.getAttribute("href")
    const saved = suppressedLinks.get(anchor)
    if (saved) {
      if (current) saved.href = current
    } else {
      if (!webLink(anchor)) return
      suppressedLinks.set(anchor, { href: current })
      if (!anchor.hasAttribute("role")) anchor.setAttribute("role", "link")
      if (!anchor.hasAttribute("tabindex")) anchor.setAttribute("tabindex", "0")
    }
    anchor.removeAttribute("href")
  }

  function suppressStatusUrls(root) {
    if (!root || !root.querySelectorAll) return
    if (root.matches && root.matches("a[href]")) suppressLink(root)
    for (const anchor of root.querySelectorAll("a[href]")) suppressLink(anchor)
  }

  function suppressedAnchor(target) {
    const anchor = target && target.closest ? target.closest("a") : null
    return anchor && suppressedLinks.has(anchor) ? anchor : null
  }

  function restoreForActivation(event) {
    const anchor = suppressedAnchor(event.target)
    if (!anchor) return
    const saved = suppressedLinks.get(anchor)
    activatingAnchor = anchor
    anchor.setAttribute("href", saved.href)
    setTimeout(function() {
      activatingAnchor = null
      suppressLink(anchor)
    }, 0)
  }

  function activateFromKeyboard(event) {
    if (event.key !== "Enter" || event.defaultPrevented) return
    const anchor = suppressedAnchor(event.target)
    if (!anchor) return
    event.preventDefault()
    anchor.click()
  }

  function applyTheme(payload) {
    const variables = model.variables(payload)
    if (!variables || payload.revision === revision) return false

    const root = document.documentElement
    if (!root) return false
    for (const [name, value] of Object.entries(variables)) root.style.setProperty(name, value)
    root.dataset.omarchyTheme = payload.mode
    root.style.colorScheme = payload.mode
    revision = payload.revision
    return true
  }

  async function refreshTheme() {
    try {
      const response = await fetch(`${themeUrl}?revision=${Date.now()}`, { cache: "no-store" })
      if (!response.ok) return false
      return applyTheme(await response.json())
    } catch (_) {
      // Keep the last valid palette, or Apple's original styling on first load.
    }
    return false
  }

  function refreshAfterWake() {
    burstPolling()
    if (!pollTimer) return
    clearTimeout(pollTimer)
    pollTimer = 0
    pollTheme()
  }

  // Mirrors of the helpers in player-model.js: the isolated and main worlds cannot
  // share code, so both copies must stay in step.
  function normalizeView(value) {
    return value === "full" ? "full" : "queue"
  }

  function formatTime(value) {
    const seconds = Math.max(0, Math.floor(Number(value) || 0))
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`
  }

  function icon(name) {
    const icons = {
      back: '<svg viewBox="0 0 24 24"><path d="m15 18-6-6 6-6"/></svg>',
      forward: '<svg viewBox="0 0 24 24"><path d="m9 18 6-6-6-6"/></svg>',
      list: '<svg viewBox="0 0 24 24"><path d="M8 6h13M8 12h13M8 18h13"/><circle cx="3" cy="6" r=".8"/><circle cx="3" cy="12" r=".8"/><circle cx="3" cy="18" r=".8"/></svg>',
      music: '<svg viewBox="0 0 24 24"><path d="M9 18V5l11-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="17" cy="16" r="3"/></svg>',
      next: '<svg viewBox="0 0 24 24"><path d="m6 5 10 7L6 19Z"/><path d="M18 5v14"/></svg>',
      orbit: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="5.25"/><circle cx="12" cy="12" r="1.6" class="omarchy-orbit-core"/></svg>',
      pause: '<svg viewBox="0 0 24 24"><path d="M8 5v14M16 5v14"/></svg>',
      play: '<svg viewBox="0 0 24 24"><path d="m8 5 11 7-11 7Z"/></svg>',
      previous: '<svg viewBox="0 0 24 24"><path d="m18 5-10 7 10 7Z"/><path d="M6 5v14"/></svg>',
      repeat: '<svg viewBox="0 0 24 24"><path d="m17 2 4 4-4 4"/><path d="M3 11V9a3 3 0 0 1 3-3h15M7 22l-4-4 4-4"/><path d="M21 13v2a3 3 0 0 1-3 3H3"/></svg>',
      search: '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="6.5"/><path d="m16 16 4 4"/></svg>',
      shuffle: '<svg viewBox="0 0 24 24"><path d="M16 3h5v5M4 20 21 3M21 16v5h-5M15 15l6 6M4 4l5 5"/></svg>'
    }
    return icons[name] || ""
  }

  function viewSwitcher(className) {
    return `<div class="omarchy-view-switcher ${className}" role="group" aria-label="Apple Music view">
      <button data-action="view" data-view="full" aria-pressed="false">Full</button>
      <button data-action="view" data-view="queue" aria-pressed="false">Queue</button>
    </div>`
  }

  function visualizerMarkup() {
    const columnWidth = 1215 / spectrumBandCount
    const wordmark = `
      <path fill-rule="evenodd" d="m720 120h-15v15h-14.998v14.999l-60.002.001v15.002l90-.002v.002h.002l-.002 89.998h-15v15h-13v15h-17v-89.998h-45v90l-45-.002v-89.998h-14.998v-30h14.998v-15.002h-14.998v-30.001h14.998v-75h15v-14.997h15v-15.002h105.002zm-90-.001h45v-74.997h-45z"/>
      <path fill-rule="evenodd" d="m105 30.002h15v14.997h15v180.001h-15v15h-15v15.002h-75v-15.002h-15v-15h-15v-180.001h15v-14.997h15v-15.002h75zm-60 194.998h45v-179.998h-45z"/>
      <path d="m300 15h60v15h15v14.999h15v180.001h-15v15h-15v15h-15l-.004-209.998h-44.994v-.002h-.002v210.002h-45v-210h-44.998v179.997h-.002v30.003h-15v-15.002h-15v-15h-14.998v-180.001h14.998v-14.999h15v-15h60v-15h45z"/>
      <path fill-rule="evenodd" d="m555 225h-15v15h-15v15h-15v-105.001l-44.998.001v105.002h-45.002v-105.002h-15v-30.001h15v-75h15.002v-14.997h15v-15.002h105zm-89.998-105.001h44.998v-74.997h-44.998z"/>
      <path d="m885 75h-15v15h-15v15h-15v-59.998h-45v179.998h45v-59.998h15v14.997h15v15.001h15v30h-15v15h-15v15.002l-105-.002v-210.001h14.998v-14.997h15.002v-15.002h105z"/>
      <path d="m960 119.999h45v-104.999h15v15h15v14.999h15v75.001h15v15h-15v90h-15v15h-15v15h-15v-105h-45v105.002l-45-.002v-105h-30v-15h15v-15.001h15v-75h15v-14.997h15v-15.002h15z"/>
      <path d="m1125 119.999h45v-104.999h15v15h15v15h15v180h-15v15h-15v15.002l-75-.002v-15h-15v-15h-15v-45.001h15v-14.997-.002h30v60h45v-75h-90v-105.001h15v-14.997h15v-15.002h15z"/>`
    const bars = Array.from({ length: spectrumBandCount }, function(_, index) {
      const x = index * columnWidth + 4
      return `<rect data-spectrum-bar="${index}" x="${x.toFixed(2)}" y="285" width="${(columnWidth - 8).toFixed(2)}" height="0" rx="3"/>`
    }).join("")
    const peaks = Array.from({ length: spectrumBandCount }, function(_, index) {
      const x = index * columnWidth + 4
      return `<rect data-spectrum-peak="${index}" x="${x.toFixed(2)}" y="285" width="${(columnWidth - 8).toFixed(2)}" height="5" rx="2"/>`
    }).join("")
    return `<div class="omarchy-visualizer" aria-hidden="true">
      <svg class="omarchy-visualizer-wordmark" viewBox="0 0 1215 285">
        <defs>
          <linearGradient id="omarchy-spectrum-color" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="1215" y2="0">
            <stop offset="0" class="omarchy-spectrum-color-low"/>
            <stop offset="0.5" class="omarchy-spectrum-color-mid"/>
            <stop offset="1" class="omarchy-spectrum-color-high"/>
          </linearGradient>
          <g id="omarchy-wordmark-shape">${wordmark}</g>
          <clipPath id="omarchy-wordmark-clip">${wordmark}</clipPath>
        </defs>
        <use href="#omarchy-wordmark-shape" class="omarchy-wordmark-base"/>
        <g class="omarchy-spectrum-bars" clip-path="url(#omarchy-wordmark-clip)">${bars}</g>
        <g class="omarchy-spectrum-peaks" clip-path="url(#omarchy-wordmark-clip)">${peaks}</g>
        <use href="#omarchy-wordmark-shape" class="omarchy-wordmark-scan"/>
        <use href="#omarchy-wordmark-shape" class="omarchy-wordmark-slice omarchy-wordmark-slice-a"/>
        <use href="#omarchy-wordmark-shape" class="omarchy-wordmark-slice omarchy-wordmark-slice-b"/>
      </svg>
    </div>`
  }

  function validSpectrum(payload) {
    if (!payload || payload.schemaVersion !== 1 || payload.active !== true || !Array.isArray(payload.bands)) return null
    if (payload.bands.length < spectrumBandCount) return null
    const bands = payload.bands.slice(0, spectrumBandCount).map(function(value) {
      const number = Number(value)
      return Number.isFinite(number) ? Math.max(0, Math.min(1, number)) : 0
    })
    return bands
  }

  function syntheticSpectrum(time) {
    return Array.from({ length: spectrumBandCount }, function(_, index) {
      const position = index / (spectrumBandCount - 1)
      const bassEnvelope = 1 - position * 0.48
      const pulse = (Math.sin(time * 0.009 + index * 1.71) + 1) * 0.5
      const drift = (Math.sin(time * 0.0031 + index * 0.47) + 1) * 0.5
      const shimmer = (Math.sin(time * 0.017 + index * 2.83) + 1) * 0.5
      return Math.min(0.86, 0.08 + bassEnvelope * (pulse * 0.34 + drift * 0.22 + shimmer * 0.1))
    })
  }

  function renderSpectrumFrame(time) {
    spectrumFrame = 0
    const root = document.getElementById("omarchy-apple-music-ui")
    if (!root) return

    const live = playerState.playing && performance.now() - spectrumLiveAt < 320
    const targets = live ? spectrumTargets : playerState.playing ? syntheticSpectrum(time) : Array(spectrumBandCount).fill(0)
    root.dataset.spectrum = live ? "live" : playerState.playing ? "fallback" : "idle"

    let moving = false
    for (let index = 0; index < spectrumBandCount; index++) {
      const target = targets[index]
      const response = target > spectrumLevels[index] ? 0.58 : 0.16
      spectrumLevels[index] += (target - spectrumLevels[index]) * response
      spectrumPeaks[index] = Math.max(spectrumLevels[index], spectrumPeaks[index] - 0.012)
      if (spectrumLevels[index] > 0.004 || target > 0.004) moving = true

      const bar = root.querySelector(`[data-spectrum-bar="${index}"]`)
      const peak = root.querySelector(`[data-spectrum-peak="${index}"]`)
      if (!bar || !peak) continue
      const height = Math.max(0, Math.min(285, spectrumLevels[index] * 285))
      const peakY = Math.max(0, Math.min(280, 285 - spectrumPeaks[index] * 285))
      bar.setAttribute("y", (285 - height).toFixed(2))
      bar.setAttribute("height", height.toFixed(2))
      peak.setAttribute("y", peakY.toFixed(2))
    }

    if (playerState.playing || moving) spectrumFrame = requestAnimationFrame(renderSpectrumFrame)
  }

  function ensureSpectrumAnimation() {
    if (!spectrumFrame) spectrumFrame = requestAnimationFrame(renderSpectrumFrame)
  }

  function scheduleSpectrumPoll(delay) {
    if (spectrumPollTimer) return
    spectrumPollTimer = setTimeout(pollSpectrum, delay)
  }

  async function pollSpectrum() {
    spectrumPollTimer = 0
    const shouldPoll = playerState.playing && panelView === "queue" && document.visibilityState === "visible"
    if (!shouldPoll) {
      scheduleSpectrumPoll(250)
      return
    }

    try {
      const response = await fetch(`${spectrumUrl}?revision=${Date.now()}`, { cache: "no-store" })
      if (response.ok) {
        const bands = validSpectrum(await response.json())
        if (bands) {
          spectrumTargets = bands
          spectrumLiveAt = performance.now()
          ensureSpectrumAnimation()
        }
      }
    } catch (_) {
      // The system analyser is optional; the visualizer keeps its animated fallback.
    }
    scheduleSpectrumPoll(spectrumPollInterval)
  }

  function playerMarkup() {
    return `
      <header class="omarchy-plugin-rail">
        <span class="omarchy-brand-mark" aria-hidden="true">${icon("orbit")}</span>
        ${viewSwitcher("omarchy-shared-view-switcher")}
        <span class="omarchy-search-slot">
          <button class="omarchy-search-button" data-action="search" aria-label="Search Apple Music" title="Search Apple Music">${icon("search")}</button>
        </span>
      </header>
      <section class="omarchy-queue-view" aria-label="Apple Music compact player">
        <div class="omarchy-now-playing">
          <div class="omarchy-artwork-wrap">
            <div class="omarchy-artwork-placeholder">${icon("music")}</div>
            <img class="omarchy-artwork" alt="" draggable="false">
          </div>
          <div class="omarchy-track-copy">
            <div class="omarchy-track-title">Nothing playing</div>
            <div class="omarchy-track-artist">Choose something in the full Apple Music view</div>
          </div>
          <div class="omarchy-progress-wrap">
            <div class="omarchy-progress-track"><span class="omarchy-progress-fill"></span><input class="omarchy-progress" type="range" min="0" max="1" step="0.1" value="0" aria-label="Playback position"></div>
            <div class="omarchy-progress-times"><span data-time="elapsed">0:00</span><span data-time="remaining">-0:00</span></div>
          </div>
          ${visualizerMarkup()}
          <div class="omarchy-player-controls">
            <button data-action="shuffle" aria-label="Toggle shuffle" title="Shuffle">${icon("shuffle")}</button>
            <button data-action="previous" aria-label="Previous track" title="Previous">${icon("previous")}</button>
            <button class="omarchy-play-button" data-action="playPause" aria-label="Play" title="Play">
              <span data-icon="play">${icon("play")}</span><span data-icon="pause" hidden>${icon("pause")}</span>
            </button>
            <button data-action="next" aria-label="Next track" title="Next">${icon("next")}</button>
            <button class="omarchy-repeat-button" data-action="repeat" aria-label="Cycle repeat mode" title="Repeat">${icon("repeat")}<span class="omarchy-repeat-one">1</span></button>
          </div>
        </div>
        <div class="omarchy-queue-panel">
          <header class="omarchy-queue-header">
            <div><span class="omarchy-eyebrow">Playing next</span><h1>Up Next</h1></div>
            <span class="omarchy-queue-count"></span>
          </header>
          <div class="omarchy-queue-list" role="list"></div>
        </div>
      </section>`
  }

  function ensurePlayerUi() {
    if (!document.body || document.getElementById("omarchy-apple-music-ui")) return false
    const root = document.createElement("div")
    root.id = "omarchy-apple-music-ui"
    root.innerHTML = playerMarkup()
    root.addEventListener("click", handlePlayerClick)
    const progress = root.querySelector(".omarchy-progress")
    progress.addEventListener("pointerdown", function() { seeking = true })
    progress.addEventListener("input", renderProgressPreview)
    progress.addEventListener("change", function() {
      seeking = false
      sendPlayerCommand("seek", Number(progress.value))
    })
    progress.addEventListener("pointerup", function() { seeking = false })
    document.body.append(root)
    scheduleSpectrumPoll(0)
    ensureSpectrumAnimation()
    applyView(panelView, false)
    receivePlayerState()
    renderPlayer()
    return true
  }

  function sendPlayerCommand(name, value) {
    const root = document.documentElement
    if (!root) return
    root.setAttribute(commandAttribute, JSON.stringify({ name, value }))
    document.dispatchEvent(new Event(commandEvent))
  }

  function applyView(value, persist) {
    panelView = normalizeView(value)
    document.documentElement.dataset.omarchyAppleMusicView = panelView
    const root = document.getElementById("omarchy-apple-music-ui")
    if (root) {
      for (const button of root.querySelectorAll("[data-action=\"view\"]")) {
        button.setAttribute("aria-pressed", String(button.dataset.view === panelView))
      }
    }
    if (panelView === "queue") scheduleSpectrumPoll(0)
    if (persist) chrome.storage.local.set({ panelView })
  }

  function openSearch() {
    applyView("full", true)
    const nativeSearch = document.querySelector('[data-testid="navigation"] [data-testid="search"]')
    if (nativeSearch) {
      nativeSearch.click()
      setTimeout(function() {
        const input = document.querySelector('[data-testid="search-input__text-field"]')
        if (input) input.focus()
      }, 100)
      return
    }

    const parts = window.location.pathname.split("/").filter(Boolean)
    const storefront = parts.length && /^[a-z]{2}$/i.test(parts[0]) ? `/${parts[0]}` : ""
    window.location.assign(`${window.location.origin}${storefront}/search`)
  }

  function handlePlayerClick(event) {
    const button = event.target.closest("button[data-action]")
    if (!button) return
    const action = button.dataset.action
    if (action === "view") applyView(button.dataset.view, true)
    else if (action === "search") openSearch()
    else if (action === "playAt") sendPlayerCommand("playAt", Number(button.dataset.index))
    else sendPlayerCommand(action)
  }

  function renderProgressPreview(event) {
    const root = document.getElementById("omarchy-apple-music-ui")
    if (!root) return
    const elapsed = Number(event.target.value)
    root.querySelector('[data-time="elapsed"]').textContent = formatTime(elapsed)
    root.querySelector('[data-time="remaining"]').textContent = `-${formatTime(Math.max(0, playerState.duration - elapsed))}`
    root.querySelector(".omarchy-progress-fill").style.width = `${playerState.duration > 0 ? elapsed / playerState.duration * 100 : 0}%`
  }

  function queueMarkupItem(item) {
    const button = document.createElement("button")
    button.className = "omarchy-queue-item"
    button.dataset.action = "playAt"
    button.dataset.index = item.index
    button.setAttribute("role", "listitem")

    const artwork = document.createElement("span")
    artwork.className = "omarchy-queue-artwork"
    if (item.artwork) {
      const image = document.createElement("img")
      image.src = item.artwork.replace("512x512", "96x96")
      image.alt = ""
      image.loading = "lazy"
      artwork.append(image)
    } else {
      artwork.innerHTML = icon("music")
    }

    const copy = document.createElement("span")
    copy.className = "omarchy-queue-copy"
    const title = document.createElement("span")
    title.className = "omarchy-queue-title"
    title.textContent = item.title
    const artist = document.createElement("span")
    artist.className = "omarchy-queue-artist"
    artist.textContent = item.artist
    copy.append(title, artist)

    const duration = document.createElement("span")
    duration.className = "omarchy-queue-duration"
    duration.textContent = item.duration ? formatTime(item.duration) : ""
    button.append(artwork, copy, duration, document.createRange().createContextualFragment(icon("play")))
    return button
  }

  function renderQueue(root) {
    const upcoming = playerState.queue.filter(function(item) { return item.index > playerState.position })
    const signature = JSON.stringify(upcoming.map(function(item) { return [item.id, item.index, item.title, item.artist, item.artwork, item.duration] }))
    if (signature === queueSignature) return
    queueSignature = signature
    const list = root.querySelector(".omarchy-queue-list")
    list.replaceChildren()
    if (upcoming.length === 0) {
      const empty = document.createElement("div")
      empty.className = "omarchy-queue-empty"
      empty.innerHTML = `${icon("list")}<strong>${playerState.nowPlaying ? "End of queue" : "Your queue is empty"}</strong><span>${playerState.nowPlaying ? "Add more music in the full view." : "Start playing something in Apple Music."}</span>`
      list.append(empty)
    } else {
      const fragment = document.createDocumentFragment()
      for (const item of upcoming) fragment.append(queueMarkupItem(item))
      list.append(fragment)
    }
    root.querySelector(".omarchy-queue-count").textContent = upcoming.length ? `${upcoming.length} track${upcoming.length === 1 ? "" : "s"}` : ""
  }

  function renderPlayer() {
    const root = document.getElementById("omarchy-apple-music-ui")
    if (!root) return
    const item = playerState.nowPlaying
    const artwork = root.querySelector(".omarchy-artwork")
    const artworkUrl = item ? item.artwork : ""
    if (artwork.dataset.src !== artworkUrl) {
      artwork.dataset.src = artworkUrl
      if (artworkUrl) artwork.src = artworkUrl
      else artwork.removeAttribute("src")
      artwork.hidden = !artworkUrl
    }
    root.querySelector(".omarchy-track-title").textContent = item ? item.title : "Nothing playing"
    root.querySelector(".omarchy-track-artist").textContent = item ? [item.artist, item.album].filter(Boolean).join(" — ") : "Choose something in the full Apple Music view"

    const progress = root.querySelector(".omarchy-progress")
    progress.max = Math.max(1, playerState.duration)
    progress.disabled = !item || playerState.duration <= 0
    if (!seeking) {
      progress.value = Math.min(playerState.time, Math.max(1, playerState.duration))
      root.querySelector(".omarchy-progress-fill").style.width = `${playerState.duration > 0 ? playerState.time / playerState.duration * 100 : 0}%`
      root.querySelector('[data-time="elapsed"]').textContent = formatTime(playerState.time)
      root.querySelector('[data-time="remaining"]').textContent = `-${formatTime(Math.max(0, playerState.duration - playerState.time))}`
    }

    root.dataset.playing = String(playerState.playing)
    root.dataset.loading = String(playerState.loading)
    ensureSpectrumAnimation()
    root.querySelector('[data-icon="play"]').hidden = playerState.playing
    root.querySelector('[data-icon="pause"]').hidden = !playerState.playing
    const playButton = root.querySelector(".omarchy-play-button")
    playButton.ariaLabel = playerState.playing ? "Pause" : "Play"
    playButton.title = playerState.playing ? "Pause" : "Play"
    root.querySelector('[data-action="shuffle"]').classList.toggle("is-active", playerState.shuffle)
    const repeat = root.querySelector('[data-action="repeat"]')
    repeat.classList.toggle("is-active", playerState.repeat !== "none")
    repeat.dataset.repeat = playerState.repeat
    for (const button of root.querySelectorAll('.omarchy-player-controls button:not([data-action="playPause"])')) button.disabled = !item
    renderQueue(root)
  }

  function receivePlayerState() {
    const value = document.documentElement.getAttribute(stateAttribute)
    if (!value) return
    try {
      playerState = JSON.parse(value)
      renderPlayer()
    } catch (_) {
      // Ignore incomplete state while the page bridge is updating the attribute.
    }
  }

  function loadView() {
    chrome.storage.local.get({ panelView: "queue" }, function(result) {
      applyView(result.panelView, false)
      ensurePlayerUi()
    })
  }

  // A theme change only lands right after a wake or another change, so the fast
  // interval is spent there and the idle window costs one fetch per second.
  function burstPolling() {
    activePollUntil = Date.now() + activePollDuration
  }

  function schedulePoll(delay) {
    if (pollTimer) return
    pollTimer = setTimeout(pollTheme, delay)
  }

  async function pollTheme() {
    pollTimer = 0
    if (await refreshTheme()) burstPolling()
    schedulePoll(Date.now() < activePollUntil ? activePollInterval : idlePollInterval)
  }

  window.addEventListener("focus", refreshAfterWake, { passive: true })
  window.addEventListener("pageshow", refreshAfterWake, { passive: true })
  document.addEventListener("click", restoreForActivation, true)
  document.addEventListener("auxclick", restoreForActivation, true)
  document.addEventListener("contextmenu", restoreForActivation, true)
  document.addEventListener("dragstart", restoreForActivation, true)
  document.addEventListener("keydown", activateFromKeyboard, true)
  document.addEventListener(stateEvent, receivePlayerState)
  document.addEventListener("visibilitychange", function() {
    if (document.visibilityState === "visible") {
      refreshAfterWake()
      scheduleSpectrumPoll(0)
      ensureSpectrumAnimation()
    }
  }, { passive: true })

  // Apple's router rewrites href on anchors that are already in the document, so
  // attribute records matter as much as added nodes.
  const linkObserver = new MutationObserver(function(records) {
    for (const record of records) {
      if (record.type !== "attributes") {
        for (const node of record.addedNodes) suppressStatusUrls(node)
        continue
      }
      const anchor = record.target
      // The restored href has to survive until the browser runs the anchor's activation.
      if (anchor === activatingAnchor) continue
      // Suppression itself removes the href, and that record must not start a loop.
      if (!anchor.matches || !anchor.matches("a[href]")) continue
      suppressLink(anchor)
    }
  })
  linkObserver.observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["href"] })

  refreshAfterWake()
  loadView()
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", ensurePlayerUi, { once: true })
  else ensurePlayerUi()
  suppressStatusUrls(document)
  pollTheme()
})()
