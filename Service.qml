import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import "AppleMusicModel.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string controlPath: sourceDir ? sourceDir + "/control.sh" : ""
  readonly property string rulesPath: sourceDir ? sourceDir + "/hypr/apple-music.lua" : ""

  property string windowAddress: ""
  property int browserPid: 0
  property bool opened: false
  property bool launching: false
  property bool rulesInstalled: false
  property string ownerScreen: ""
  property var lastAnchor: null
  property var monitors: []
  property bool dismissArmed: false
  property string lastError: ""

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: Model.playerForPid(players, browserPid)
  readonly property bool hasMedia: activePlayer !== null
    && !!(activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? String(activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? String(activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer ? String(activePlayer.trackAlbum || "") : ""
  readonly property string artUrl: activePlayer ? String(activePlayer.trackArtUrl || "") : ""
  readonly property bool playing: activePlayer ? activePlayer.isPlaying === true : false

  property string stateIntent: ""
  property var stateAnchor: null
  property string stateOutput: ""
  property string queuedIntent: ""
  property var queuedAnchor: null
  property bool syncQueued: false
  property int launchAttempts: 0
  property var launchAnchor: null
  property string actionKind: ""

  function notifyFailure(message) {
    lastError = String(message || "Apple Music could not be opened")
    Quickshell.execDetached(["omarchy-notification-send", "Apple Music", lastError])
  }

  function requestState(intent, anchor) {
    var nextIntent = String(intent || "sync")
    if (stateProc.running) {
      if (nextIntent !== "sync") {
        queuedIntent = nextIntent
        queuedAnchor = anchor || lastAnchor
      } else {
        syncQueued = true
      }
      return
    }

    stateIntent = nextIntent
    stateAnchor = anchor || lastAnchor
    stateOutput = ""
    stateProc.command = [controlPath, "state"]
    stateProc.running = controlPath !== ""
  }

  function drainStateQueue() {
    if (queuedIntent !== "") {
      var intent = queuedIntent
      var anchor = queuedAnchor
      queuedIntent = ""
      queuedAnchor = null
      requestState(intent, anchor)
    } else if (syncQueued) {
      syncQueued = false
      requestState("sync", null)
    }
  }

  function syncState(state) {
    var client = state && state.client ? state.client : null
    monitors = state && Array.isArray(state.monitors) ? state.monitors : []
    windowAddress = client ? Model.normalizeAddress(client.address) : ""
    browserPid = client ? (parseInt(client.pid, 10) || 0) : 0
    if (client) lastError = ""
    opened = !!(state && state.open && windowAddress)
    if (opened && !dismissArmed) dismissDelay.restart()
    if (!opened) {
      dismissArmed = false
      dismissDelay.stop()
    }
    ownerScreen = opened && state && state.openScreen ? String(state.openScreen) : ""
  }

  function handleState(raw, intent, anchor) {
    var state
    try {
      state = JSON.parse(String(raw || "{}"))
    } catch (error) {
      if (intent !== "sync" && intent !== "awaitLaunch")
        notifyFailure("Could not read the Hyprland window state")
      return
    }

    syncState(state)

    if (intent === "toggle") {
      if (opened) hide()
      else if (state.client) showExisting(state.client, state.monitors, anchor)
      else launch(anchor)
    } else if (intent === "show") {
      if (state.client) showExisting(state.client, state.monitors, anchor)
      else launch(anchor)
    } else if (intent === "awaitLaunch") {
      if (state.client) {
        launchPoll.stop()
        launching = false
        showExisting(state.client, state.monitors, launchAnchor)
      } else if (launchAttempts >= 40) {
        launchPoll.stop()
        launching = false
        notifyFailure("Chromium did not create the Apple Music window")
      }
    }
  }

  function launch(anchor) {
    if (launching || launchProc.running) return
    launching = true
    lastError = ""
    launchAttempts = 0
    launchAnchor = anchor || lastAnchor
    launchProc.command = [controlPath, "launch"]
    launchProc.running = true
  }

  function showExisting(client, availableMonitors, anchor) {
    var actualAnchor = anchor || lastAnchor || ({
      screenName: "",
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      barPosition: "top"
    })
    var monitor = Model.monitorFor(availableMonitors, actualAnchor.screenName)
    var priorSize = client && Array.isArray(client.size) ? client.size : []
    var desiredWidth = Number(priorSize[0]) >= 480 ? Number(priorSize[0]) : 960
    var desiredHeight = Number(priorSize[1]) >= 360 ? Number(priorSize[1]) : 720
    var rect = Model.placement(actualAnchor, monitor, desiredWidth, desiredHeight, 12)
    var address = Model.normalizeAddress(client && client.address)
    if (!monitor || !rect || !address) {
      notifyFailure("Could not place the Apple Music window")
      return
    }

    lastAnchor = actualAnchor
    windowAddress = address
    browserPid = parseInt(client.pid, 10) || 0
    ownerScreen = String(monitor.name || actualAnchor.screenName || "")
    dismissArmed = false
    actionKind = "show"
    actionProc.command = [
      controlPath, "show", address, ownerScreen,
      String(rect.x), String(rect.y), String(rect.width), String(rect.height)
    ]
    actionProc.running = true
  }

  function show(anchor) {
    if (anchor) lastAnchor = anchor
    requestState("show", anchor || lastAnchor)
  }

  function hide() {
    if ((!opened && !windowAddress) || actionProc.running) return
    dismissArmed = false
    actionKind = "hide"
    actionProc.command = [controlPath, "hide", windowAddress]
    actionProc.running = true
  }

  function toggle(anchor) {
    if (anchor) lastAnchor = anchor
    requestState("toggle", anchor || lastAnchor)
  }

  function runAction(action) {
    var player = activePlayer
    if (!player) return false

    if (action === "next" && player.canGoNext) {
      player.next()
      return true
    }
    if (action === "previous" && player.canGoPrevious) {
      player.previous()
      return true
    }
    if (action === "playPause") {
      if (player.isPlaying && player.canPause) player.pause()
      else if (!player.isPlaying && player.canPlay) player.play()
      else if (player.canTogglePlaying) player.togglePlaying()
      else return false
      return true
    }
    return false
  }

  function installRules(force) {
    if (!controlPath || !rulesPath || rulesProc.running) return
    rulesProc.command = [controlPath, "rules", rulesPath, force ? "true" : "false"]
    rulesProc.running = true
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (name === "configreloaded") {
      ruleReload.restart()
      return
    }

    if (name === "openwindow" || name === "activespecial") {
      requestState("sync", null)
      return
    }

    if (name === "closewindow") {
      var closed = Model.normalizeAddress(Model.eventParts(event, 1)[0])
      if (closed && closed === windowAddress) {
        windowAddress = ""
        browserPid = 0
        opened = false
        ownerScreen = ""
        dismissArmed = false
      }
      return
    }

    if (name === "activewindowv2" && dismissArmed) {
      var focused = Model.normalizeAddress(Model.eventParts(event, 1)[0])
      if (Model.shouldDismissWindow(opened, focused, windowAddress)) hide()
    }
  }

  onControlPathChanged: {
    if (!controlPath) return
    installRules(false)
    requestState("sync", null)
  }

  Component.onCompleted: Qt.callLater(function() {
    installRules(false)
    requestState("sync", null)
  })

  Process {
    id: stateProc
    stdout: StdioCollector {
      onStreamFinished: root.stateOutput = text
    }
    onExited: function(code) {
      var intent = root.stateIntent
      var anchor = root.stateAnchor
      root.stateIntent = ""
      root.stateAnchor = null
      if (code === 0) root.handleState(root.stateOutput, intent, anchor)
      else if (intent !== "sync" && intent !== "awaitLaunch")
        root.notifyFailure("Hyprland is not available")
      Qt.callLater(root.drainStateQueue)
    }
  }

  Process {
    id: launchProc
    onExited: function(code) {
      if (code !== 0) {
        root.launching = false
        root.notifyFailure("Could not launch the configured Chromium browser")
        return
      }
      launchPoll.restart()
    }
  }

  Timer {
    id: launchPoll
    interval: 250
    repeat: true
    onTriggered: {
      root.launchAttempts++
      root.requestState("awaitLaunch", root.launchAnchor)
    }
  }

  Process {
    id: actionProc
    onExited: function(code) {
      if (code !== 0) {
        root.notifyFailure(root.actionKind === "hide"
          ? "Could not hide the Apple Music window"
          : "Could not position the Apple Music window")
      } else {
        root.lastError = ""
        if (root.actionKind === "show") {
          root.opened = true
          dismissDelay.restart()
        } else if (root.actionKind === "hide") {
          root.opened = false
          root.ownerScreen = ""
        }
      }
      root.actionKind = ""
      stateRefresh.restart()
    }
  }

  Timer {
    id: dismissDelay
    interval: 350
    onTriggered: root.dismissArmed = root.opened
  }

  Timer {
    id: stateRefresh
    interval: 250
    onTriggered: root.requestState("sync", null)
  }

  Process {
    id: rulesProc
    onExited: function(code) {
      root.rulesInstalled = code === 0
      if (code !== 0) console.warn("apple-music: could not install runtime window rules")
    }
  }

  Timer {
    id: ruleReload
    interval: 400
    onTriggered: root.installRules(true)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  IpcHandler {
    target: "apple-music"

    function open(): string { root.show(root.lastAnchor); return "ok" }
    function close(): string { root.hide(); return "ok" }
    function show(): string { root.show(root.lastAnchor); return "ok" }
    function hide(): string { root.hide(); return "ok" }
    function toggle(): string { root.toggle(root.lastAnchor); return "ok" }
    function playPause(): string { return root.runAction("playPause") ? "ok" : "unavailable" }
    function next(): string { return root.runAction("next") ? "ok" : "unavailable" }
    function previous(): string { return root.runAction("previous") ? "ok" : "unavailable" }
    function ping(): string { return "ok" }

    function status(): string {
      return JSON.stringify({
        windowAddress: root.windowAddress,
        browserPid: root.browserPid,
        opened: root.opened,
        launching: root.launching,
        ownerScreen: root.ownerScreen,
        rulesInstalled: root.rulesInstalled,
        hasMedia: root.hasMedia,
        playing: root.playing,
        title: root.title,
        artist: root.artist,
        lastError: root.lastError,
        sourceDir: root.sourceDir
      })
    }
  }
}
