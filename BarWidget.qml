import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "AppleMusicModel.js" as Model

BarWidget {
  id: root
  moduleName: Model.PLUGIN_ID

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(Model.PLUGIN_ID)
    : null
  readonly property string displayMode: Model.normalizeDisplay(setting("display", "icon"))
  readonly property bool playerMode: !vertical && displayMode === "player"
  readonly property string screenName: {
    var window = root.QsWindow ? root.QsWindow.window : null
    return window && window.screen ? String(window.screen.name || "") : ""
  }
  readonly property bool opened: service
    ? service.opened && service.ownerScreen === screenName
    : false
  readonly property bool hasMedia: service ? service.hasMedia : false
  readonly property bool playing: service ? service.playing : false
  readonly property string playIcon: playing ? "󰏤" : "󰐊"
  readonly property string title: service ? service.title : ""
  readonly property string artist: service ? service.artist : ""
  readonly property string statusText: hasMedia
    ? title + (artist ? "  ·  " + artist : "")
    : "Apple Music"
  implicitWidth: playerMode ? mediaRow.implicitWidth + Style.space(14) : Style.bar.iconSlot
  implicitHeight: barSize
  property real maxLabelWidth: Style.space(180)
  readonly property real openPanelIndicatorWidth: playerMode
    ? implicitWidth
    : Style.bar.iconCanvas

  function anchorPayload() {
    var point = { x: 0, y: 0 }
    try { point = root.mapToItem(null, 0, 0) } catch (error) {}
    return {
      screenName: screenName,
      x: point.x,
      y: point.y,
      width: root.width,
      height: root.height,
      barPosition: bar ? bar.position : "top"
    }
  }

  function open() {
    if (!service) return
    if (bar && typeof bar.requestPopout === "function") bar.requestPopout(root)
    service.show(anchorPayload())
  }

  function close() {
    if (service) service.hide()
  }

  function closeForPopoutSwitch() { close() }

  function toggle() {
    if (!service) return
    if (opened) close()
    else open()
  }

  function toggleDisplay() {
    var next = Model.toggledDisplay(displayMode)
    Quickshell.execDetached(["omarchy", "bar", "set", Model.PLUGIN_ID, "display", next])
  }

  function runTransport(action) {
    if (service) service.runAction(action)
  }

  function handleClick(button) {
    var buttonName = button === Qt.MiddleButton
      ? "middle"
      : button === Qt.RightButton ? "right" : "left"
    var action = Model.clickAction(displayMode, buttonName)
    if (action === "toggleDisplay") toggleDisplay()
    else if (action === "playPause" && hasMedia) runTransport("playPause")
    else toggle()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(root, direction)
    return false
  }

  function syncPopout() {
    if (!bar) return
    if (opened) {
      if (bar.activePopout !== root) bar.requestPopout(root)
    } else if (bar.activePopout === root) {
      bar.releasePopout(root)
    }
  }

  onOpenedChanged: syncPopout()
  onBarChanged: syncPopout()
  Component.onDestruction: if (bar && bar.activePopout === root) bar.releasePopout(root)

  Item {
    anchors.centerIn: parent
    width: root.playerMode ? mediaRow.implicitWidth : Style.bar.iconCanvas
    height: Style.bar.iconCanvas

    MusicMark {
      anchors.centerIn: parent
      visible: !root.playerMode
      width: Style.bar.iconCanvas
      height: width
      playing: root.playing
      ink: root.bar ? root.bar.barForeground : Color.foreground
      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
      markOpacity: root.hasMedia && !root.playing ? 0.72 : 1.0
    }

    Row {
      id: mediaRow
      anchors.centerIn: parent
      visible: root.playerMode
      spacing: Style.space(6)

      Text {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        text: root.hasMedia ? root.playIcon : "󰝚"
        color: root.playing
          ? (root.bar ? root.bar.barForeground : Color.foreground)
          : Qt.darker(root.bar ? root.bar.barForeground : Color.foreground, 1.5)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      Item {
        id: scrollClip
        width: Math.min(root.maxLabelWidth, labelText.implicitWidth)
        height: glyph.height
        clip: true
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: labelText
          text: root.statusText
          textFormat: Text.PlainText
          color: root.bar ? root.bar.barForeground : Color.foreground
          opacity: root.hasMedia ? 1.0 : 0.58
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
          anchors.verticalCenter: parent.verticalCenter
          renderType: Text.NativeRendering

          property bool needsScroll: implicitWidth > scrollClip.width

          NumberAnimation on x {
            running: labelText.needsScroll && !root.opened && root.playerMode
            loops: Animation.Infinite
            duration: Math.max(6000, labelText.implicitWidth * 25)
            from: scrollClip.width
            to: -labelText.implicitWidth
            easing.type: Easing.Linear
          }
        }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      root.handleClick(mouse.button)
    }

    onWheel: function(wheel) {
      if (!root.hasMedia) return
      if (wheel.angleDelta.y > 0) root.runTransport("previous")
      else if (wheel.angleDelta.y < 0) root.runTransport("next")
    }

    onEntered: if (root.bar) root.bar.showTooltip(root,
      root.playerMode
        ? "Apple Music — Left-click to play/pause; middle-click for compact mode; right-click to open"
        : "Apple Music — Left or right-click to open; middle-click for now playing")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
