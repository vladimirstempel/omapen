import QtQuick
import qs.Commons
import qs.Ui

// Every button on this panel: the kit's Button in the bar's colours, carrying
// the accent focus ring.
Button {
  id: root

  property var bar
  // The kit centres icon and label together as one row. A digit is a marker
  // rather than part of the name, so it is drawn on the left edge instead and
  // the label keeps the whole button to centre itself in. Pass an icon through
  // iconText as usual when there is no digit to show.
  property string digit: ""

  foreground: bar.foreground
  fontFamily: bar.fontFamily
  bordered: true
  focusable: true

  Text {
    visible: root.digit !== ""
    text: root.digit
    color: root.selected ? Style.selectedStateColor(root.foreground, root.accent) : root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.iconSize
    anchors.left: parent.left
    anchors.leftMargin: root.leftPadding
    anchors.verticalCenter: parent.verticalCenter
  }

  FocusRing {}
}
