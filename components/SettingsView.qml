import QtQuick
import QtQuick.Controls as Controls
import Quickshell.Io
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


  // The ids the selected agent can run, from `omapen models`. Empty means the
  // agent has no list, and the model is then typed into a field.
  property var models: []
  property bool loadingModels: false
  // The model is one the list does not have, so it is typed by hand.
  property bool customModel: false
  // The list entry that opens the field. No agent has a model with this id.
  readonly property string otherModel: "\u0000other"
  readonly property var modelOptions: {
    var options = [{ value: "", label: "The agent's default" }]
    for (var i = 0; i < models.length; i++) options.push(models[i])
    options.push({ value: otherModel, label: "Other..." })
    return options
  }

  // In the order Tab walks them.
  readonly property var stops: {
    var ring = [agentGroup]
    if (modelPicker.visible) ring.push(modelPicker)
    if (modelField.visible) ring.push(modelField)
    ring.push(resultGroup, captureToggle, widthField.field)
    return ring
  }
  // A focused control here owns its keys: h and l walk a group, and digits are
  // typed into a field. The panel's key catcher stands down while one has it.
  // An open list counts too: its search field is outside the focus ring.
  readonly property bool editing: {
    if (modelDropdown.popupOpen) return true
    for (var i = 0; i < stops.length; i++) if (stops[i].activeFocus) return true
    return false
  }

  spacing: Style.space(10)

  onSavedModelChanged: syncModel()
  onCustomModelChanged: syncModel()
  onAgentChanged: loadModels()
  // Each time the settings open: a model pulled since the last look is there.
  onVisibleChanged: if (visible) loadModels()
  Component.onCompleted: {
    syncModel()
    if (visible) loadModels()
  }

  // The list writes its own value when a row is picked, which ends a binding.
  // So the value is set by hand, here.
  function syncModel() {
    modelField.text = savedModel
    modelDropdown.value = customModel ? otherModel : savedModel
  }

  function saveModel() {
    var model = modelField.text.trim()
    if (model !== root.savedModel) panel.persistSettings({ model: model })
  }

  function loadModels() {
    // A run for another agent is still out. Its exit starts this one.
    if (modelsProc.running) return
    modelsProc.agent = root.agent
    modelsProc.command = [panel.cli, "models", root.agent]
    root.models = []
    root.customModel = false
    root.loadingModels = true
    modelsProc.running = true
  }

  function pickModel(value) {
    if (value === otherModel) {
      root.customModel = true
      Qt.callLater(function () { modelField.forceActiveFocus() })
      return
    }
    root.customModel = false
    if (value !== root.savedModel) panel.persistSettings({ model: value })
    syncModel()
  }

  // The first thing under an item that Tab can stop on. The list keeps its
  // trigger to itself, and that is the part that has to hold the focus.
  function tabStop(item) {
    for (var i = 0; i < item.children.length; i++) {
      var child = item.children[i]
      if (child.activeFocusOnTab) return child
      var deeper = tabStop(child)
      if (deeper) return deeper
    }
    return null
  }

  Process {
    id: modelsProc
    property string agent: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (modelsProc.agent !== root.agent) return
        var lines = String(text || "").split("\n")
        var ids = []
        for (var i = 0; i < lines.length; i++) {
          var id = lines[i].trim()
          if (id !== "") ids.push(id)
        }
        root.models = ids
        // A saved model the list does not have was typed by hand, and one
        // with no list at all goes in the field anyway.
        root.customModel = ids.length > 0 && root.savedModel !== "" && ids.indexOf(root.savedModel) < 0
        root.syncModel()
      }
    }
    onExited: {
      if (modelsProc.agent !== root.agent) {
        root.loadModels()
        return
      }
      root.loadingModels = false
    }
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

  // Holds the focus ring's place for the list, and hands the focus on to the
  // list's own trigger, which is what opens it on Return.
  FocusScope {
    id: modelPicker
    width: root.width
    height: modelDropdown.implicitHeight
    visible: root.loadingModels || root.models.length > 0
    onActiveFocusChanged: {
      if (!activeFocus) return
      var trigger = root.tabStop(modelDropdown)
      if (trigger && !trigger.activeFocus) trigger.forceActiveFocus()
    }

    SearchableDropdown {
      id: modelDropdown
      width: parent.width
      showLabel: false
      options: root.modelOptions
      placeholderText: "Search models"
      emptyText: "No model matches"
      foreground: root.bar.foreground
      fontFamily: root.bar.fontFamily
      onChanged: function (value) { root.pickModel(value) }
    }
  }

  TextField {
    id: modelField
    visible: !modelPicker.visible || root.customModel
    width: root.width
    foreground: root.bar.foreground
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.body
    placeholderText: root.customModel ? "A model id" : "The agent's default"
    maximumLength: 256
    readonly property bool singleLine: true
    // Qt's own paste is closed, and a paste goes through the panel.
    Controls.ContextMenu.menu: null
    PasteGuard { input: modelField; panel: root.panel }
    Keys.onPressed: function (event) { if (root.panel.pasteKey(event, modelField)) event.accepted = true }
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
