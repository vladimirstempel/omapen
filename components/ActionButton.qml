import QtQuick
import qs.Ui

// Every button on this panel: the kit's Button in the bar's colours, carrying
// the accent focus ring.
Button {
  property var bar

  foreground: bar.foreground
  fontFamily: bar.fontFamily
  bordered: true
  focusable: true

  FocusRing {}
}
