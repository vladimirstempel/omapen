import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Qt's TextArea wearing the border, fill and padding of Ui/TextField, which is
// the same trick one level down: a styled Qt TextField. The kit ships no
// multi-line input, and what gets pasted in here is a paragraph often enough
// that a single line was the wrong shape.
Flickable {
  id: root

  property var bar
  property var panel
  property alias text: input.text
  readonly property alias input: input
  readonly property bool editing: input.activeFocus

  // The panel clamps its own height and never scrolls, so the field caps
  // itself. Past six lines a paste scrolls in here rather than pushing the
  // actions off the bottom.
  readonly property real maxHeight: Style.font.body * 1.6 * 6
    + input.topPadding + input.bottomPadding

  height: Math.min(input.implicitHeight, maxHeight)
  clip: true
  flickableDirection: Flickable.VerticalFlick
  boundsBehavior: Flickable.StopAtBounds

  // Attached rather than nested: this is what keeps the caret in view when you
  // type past the bottom of the box.
  TextArea.flickable: TextArea {
    id: input

    readonly property var borderSpec: Border.controlSpec(
      activeFocus ? "focus" : (hovered ? "hover-cursor" : "normal"),
      root.bar.foreground, Color.accent)

    wrapMode: TextArea.Wrap
    selectByMouse: true
    placeholderText: "Paste or type the text to work on"
    color: root.bar.foreground
    placeholderTextColor: Qt.darker(root.bar.foreground, 1.6)
    selectionColor: Style.selectionFillFor(root.bar.foreground, Color.accent)
    selectedTextColor: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body

    leftPadding: Style.spacing.controlPaddingX + Border.left(borderSpec)
    rightPadding: Style.spacing.controlPaddingX + Border.right(borderSpec)
    topPadding: Style.spacing.inputPaddingY + Border.top(borderSpec)
    bottomPadding: Style.spacing.inputPaddingY + Border.bottom(borderSpec)

    background: BorderSurface {
      color: Style.controlFill(input.activeFocus, input.hovered,
        root.bar.foreground, Color.accent)
      borderSpec: input.borderSpec
      radius: Style.cornerRadius
    }

    // The key catcher is blocked while this field has focus, so the keys that
    // leave it are handled here. Return is not one of them: it breaks the
    // line, and Tab is what moves on.
    Keys.onTabPressed: function (event) { event.accepted = true; root.panel.moveFocus(1) }
    Keys.onBacktabPressed: function (event) { event.accepted = true; root.panel.moveFocus(-1) }
    Keys.onPressed: function (event) { if (root.panel.presetShortcut(event)) event.accepted = true }
    Keys.onEscapePressed: function (event) {
      event.accepted = true
      root.panel.close()
    }
  }
}
