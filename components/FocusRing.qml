import QtQuick
import qs.Commons

// The kit draws its focus ring in the foreground colour, which on a panel of
// bordered buttons is nearly invisible. Keyboard users need to see where they
// are at a glance, so the ring is redrawn in the theme accent.
Rectangle {
  anchors.fill: parent
  visible: parent.activeFocus
  color: "transparent"
  radius: Style.cornerRadius
  border.width: 2
  border.color: Color.accent
}
