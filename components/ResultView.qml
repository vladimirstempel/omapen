import QtQuick
import qs.Commons

Flickable {
  id: root

  property var bar
  property string body: ""

  implicitHeight: Math.min(text.implicitHeight, Style.space(260))
  contentHeight: text.implicitHeight
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  Text {
    id: text
    width: root.width
    text: root.body
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
  }
}
