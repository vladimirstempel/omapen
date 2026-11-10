import QtQuick
import qs.Commons
import qs.Ui

// The plugin's settings, inside its own panel. Every value here is one key on
// the plugin's entry in shell.json, which is the same place bin/omapen reads,
// so a change takes effect on the next run with nothing to restart.
Column {
  id: root

  property var bar
  // The Panel: setting(), persistSettings(), moveFocus() and closeSettings().
  property var panel

  readonly property var agents: ["System default", "claude", "pi", "omp", "ollama"]
  readonly property var resultModes: ["Show in panel", "Replace the selection"]
  readonly property string agent: String(panel.setting("agent", "System default"))
  readonly property string savedModel: String(panel.setting("model", ""))

  // In the order Tab walks them.
  readonly property var stops: [agentGroup, modelField, resultGroup, captureToggle, widthField.field]
  // A focused control here owns its keys: h and l walk a group, and digits are
  // typed into a field. The panel's key catcher stands down while one has it.
  readonly property bool editing: {
    for (var i = 0; i < stops.length; i++) if (stops[i].activeFocus) return true
    return false
  }

  spacing: Style.space(10)

  onSavedModelChanged: modelField.text = savedModel
  Component.onCompleted: modelField.text = savedModel

  function saveModel() {
    var model = modelField.text.trim()
    if (model !== root.savedModel) panel.persistSettings({ model: model })
  }

  // The key catcher is blocked while a control here has focus, so the keys
  // that leave it are handled on the way up.
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      panel.closeSettings()
    } else if (event.key === Qt.Key_Backtab
        || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
      panel.moveFocus(-1)
    } else if (event.key === Qt.Key_Tab) {
      panel.moveFocus(1)
    } else {
      return
    }
    event.accepted = true
  }

  component Caption: Text {
    width: root.width
    textFormat: Text.PlainText
    color: Qt.darker(root.bar.foreground, 1.4)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.Wrap
  }

  Caption { text: "Agent" }

  ButtonGroup {
    id: agentGroup
    options: root.agents
    value: root.agent
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    // A model id belongs to the agent it was picked for, and a stale one fails
    // the run instead of being ignored. So it goes when the agent does.
    onChanged: function (value) {
      if (value !== root.agent) root.panel.persistSettings({ agent: value, model: "" })
    }
  }

  Caption {
    text: root.agent === "System default"
      ? "Follows Setup > Default agent."
      : (root.agent === "ollama"
        ? "Runs a model on this machine."
        : "Uses " + root.agent + ", and fails plainly when it is not installed.")
  }

  Caption { text: "Model" }

  TextField {
    id: modelField
    width: root.width
    foreground: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    placeholderText: "The agent's default"
    onEditingFinished: root.saveModel()
  }

  Caption { text: "What to do with the result" }

  ButtonGroup {
    id: resultGroup
    options: root.resultModes
    value: String(root.panel.setting("resultMode", "Show in panel"))
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    onChanged: function (value) { root.panel.persistSettings({ resultMode: value }) }
  }

  Toggle {
    id: captureToggle
    width: root.width
    label: "Read the focused window"
    description: "Sends Ctrl+C to the window in front to get its selection. Off reads whatever was last highlighted."
    checked: root.panel.setting("captureFallback", true) !== false
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    onClicked: root.panel.persistSettings({ captureFallback: !checked })
  }

  NumberField {
    id: widthField
    label: "Panel width"
    from: 320
    to: 900
    stepSize: 20
    value: Number(root.panel.setting("panelWidth", 540)) || 540
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    onModified: function (value) { root.panel.persistSettings({ panelWidth: value }) }
  }
}
