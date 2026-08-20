(function() {
  "use strict"

  const model = globalThis.OmarchyAppleMusicTheme
  const themeUrl = chrome.runtime.getURL("theme.json")
  const pollInterval = 100
  let revision = ""

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
      if (!response.ok) return
      applyTheme(await response.json())
    } catch (_) {
      // Keep the last valid palette, or Apple's original styling on first load.
    }
  }

  function refreshAfterWake() {
    refreshTheme()
  }

  async function pollTheme() {
    await refreshTheme()
    setTimeout(pollTheme, pollInterval)
  }

  window.addEventListener("focus", refreshAfterWake, { passive: true })
  window.addEventListener("pageshow", refreshAfterWake, { passive: true })
  document.addEventListener("visibilitychange", function() {
    if (document.visibilityState === "visible") refreshAfterWake()
  }, { passive: true })

  refreshAfterWake()
  setTimeout(pollTheme, pollInterval)
})()
