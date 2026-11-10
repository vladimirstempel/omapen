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
    // The rewrite is made from text captured off the screen, so it is drawn as
    // written. Left to guess, Qt reads markup in it as rich text, and an <img>
    // tag in there loads whatever it points at.
    textFormat: Text.PlainText
    text: root.body
    color: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
  }
}
