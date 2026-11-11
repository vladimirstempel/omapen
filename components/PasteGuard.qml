import QtQuick

// Goes over an editable field and takes the middle button, which is how Qt
// pastes the PRIMARY selection on its own, to the end and with no deadline.
// The paste goes through the panel, which reads it with both. Every other
// button falls through to the field.
MouseArea {
  property var input
  property var panel

  anchors.fill: parent
  acceptedButtons: Qt.MiddleButton
  cursorShape: Qt.IBeamCursor
  onClicked: function (mouse) {
    input.forceActiveFocus()
    input.cursorPosition = input.positionAt(mouse.x, mouse.y)
    panel.paste(input, true)
  }
}
