import QtQuick

Item {
  id: root

  property bool playing: false
  property color ink: "white"
  property string fontFamily: "sans-serif"
  property real markOpacity: 1.0

  opacity: markOpacity

  Text {
    anchors.centerIn: parent
    visible: !root.playing
    text: "󰝚"
    color: root.ink
    font.family: root.fontFamily
    font.pixelSize: Math.max(13, Math.round(Math.min(parent.width, parent.height)))
    renderType: Text.NativeRendering
  }

  Row {
    anchors.centerIn: parent
    visible: root.playing
    spacing: Math.max(1, Math.round(parent.width * 0.08))

    Repeater {
      model: [0.48, 0.78, 0.6]

      Item {
        required property real modelData
        required property int index

        width: Math.max(2, Math.round(root.width * 0.14))
        height: Math.max(12, Math.round(root.height * 0.86))

        Rectangle {
          id: bar
          anchors.bottom: parent.bottom
          width: parent.width
          height: parent.height * parent.modelData
          radius: width / 2
          color: root.ink

          SequentialAnimation on height {
            running: root.playing
            loops: Animation.Infinite
            NumberAnimation {
              to: bar.parent.height * ([0.86, 0.42, 0.92][bar.parent.index])
              duration: 240 + bar.parent.index * 70
              easing.type: Easing.InOutSine
            }
            NumberAnimation {
              to: bar.parent.height * bar.parent.modelData
              duration: 260 + bar.parent.index * 55
              easing.type: Easing.InOutSine
            }
          }
        }
      }
    }
  }
}
