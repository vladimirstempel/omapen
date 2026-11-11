import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

TextField {
  id: root

  property var bar
  property var panel
  readonly property var input: root
  readonly property bool editing: root.activeFocus

  foreground: bar.foreground
  font.family: bar.fontFamily
  font.pixelSize: Style.font.body

  // An instruction, not a document.
  maximumLength: 16384
  // One line: a pasted line break becomes a space.
  readonly property bool singleLine: true
  // Qt's own paste is closed, the same as in the text field above it.
  Controls.ContextMenu.menu: null
  PasteGuard { input: root; panel: root.panel }

  // The key catcher is blocked while this field has focus, so the keys that
  // leave it are handled here.
  Keys.onTabPressed: function (event) { event.accepted = true; root.panel.moveFocus(1) }
  Keys.onBacktabPressed: function (event) { event.accepted = true; root.panel.moveFocus(-1) }
  Keys.onPressed: function (event) {
    if (root.panel.pasteKey(event, root) || root.panel.presetShortcut(event)) event.accepted = true
  }
  // Return has to be swallowed here. Unaccepted it bubbles up to the key
  // catcher, which reads it as "activate" and closes the panel out from under
  // the run that just started. Ctrl+Return applies the result, so the whole
  // thing is reachable from the keyboard: open, type, Return, Ctrl+Return.
  Keys.onReturnPressed: function (event) {
    event.accepted = true
    root.panel.submit(event.modifiers & Qt.ControlModifier)
  }
  Keys.onEnterPressed: function (event) {
    event.accepted = true
    root.panel.submit(event.modifiers & Qt.ControlModifier)
  }
  Keys.onEscapePressed: function (event) {
    event.accepted = true
    root.panel.close()
  }
}
