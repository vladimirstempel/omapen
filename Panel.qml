pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "./components"

// Bar button plus its popup. The popup is the whole plugin UI: the text that
// was captured, the rewrite actions, and the result. Everything that touches
// the clipboard, the compositor or the agent lives in bin/omapen instead, so it
// can be driven from a terminal with no shell running.
Panel {
  id: root
  moduleName: "omapen"
  ipcTarget: "omapen"

  // The bar sizes a widget slot from the root item's implicit size, and this
  // root is a plain Item whose only visual child fills it. Without this the
  // slot is zero wide and the button never paints.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")
  readonly property string cli: pluginDir + "bin/omapen"
  readonly property string stateDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omapen"

  property var presets: []
  property string sourceText: ""
  property string sourceKind: ""
  property string result: ""
  property string errorText: ""
  property string pending: ""      // preset id or "-" while a run is in flight
  readonly property bool busy: runProc.running
  readonly property bool replaceMode: root.setting("resultMode", "Show in panel") === "Replace the selection"

  // Compose mode: opened with nothing captured, so the panel supplies the text
  // instead of the screen. There is no window behind it to paste into, which
  // is why Replace disappears and Copy is the way out.
  // The free prompt lives behind the Custom action rather than beside it. Nine
  // buttons make a square, and a field that is always open reads as the main
  // way in when it is the one people reach for least.
  property bool customOpen: false
  readonly property string customDigit: root.presets.length < 9 ? String(root.presets.length + 1) : ""

  readonly property bool manual: root.sourceKind === "manual"
  readonly property string workingText: root.manual ? sourceField.text.trim() : root.sourceText

  onOpenedChanged: {
    if (opened) {
      result = ""
      errorText = ""
      promptField.text = ""
      sourceField.text = ""
      customOpen = false
      sessionFile.reload()
    } else if (runProc.running) {
      runProc.running = false
    }
  }

  function ask(presetId, free) {
    if (root.workingText === "") return
    // Picking an action off the grid is a choice against the one Custom holds,
    // so its field goes away with it. Every caller comes through here, the
    // click and the Alt digit alike.
    if (!free) root.customOpen = false
    result = ""
    errorText = ""
    pending = free ? "-" : presetId
    runProc.command = free ? [root.cli, "run", "-", free] : [root.cli, "run", presetId]
    // The agent reads the session file, so typed text has to land there first
    // rather than travel alongside the run.
    if (root.manual) {
      setTextProc.command = [root.cli, "settext", root.workingText]
      setTextProc.running = true
    } else {
      runProc.running = true
    }
  }

  function submit(apply) {
    if (apply) {
      // Ctrl+Return is "paste it back", which compose mode has no window for.
      if (!root.manual && root.result !== "") root.apply()
    } else if (promptField.text !== "") {
      root.ask("", promptField.text)
    }
  }

  // A second press puts the field away again, so the button reads as the
  // on/off switch it looks like. Focus follows it either way, or it would be
  // left sitting on a field that is no longer there.
  function toggleCustom() {
    root.customOpen = !root.customOpen
    if (root.customOpen) promptField.input.forceActiveFocus()
    else customButton.forceActiveFocus()
  }

  function retry() {
    if (pending === "-") ask("", promptField.text)
    else ask(pending, "")
  }

  // Close first: insert focuses the window the text came from, and the popup is
  // holding the keyboard until it goes away.
  function apply() {
    root.close()
    insertProc.running = true
  }

  // Omarchy is a keyboard-first desktop, so everything the panel can do has to
  // be reachable without a pointer. Focus moves over an explicit ring rather
  // than Qt's focus chain, which would happily walk out of the panel and into
  // the rest of the shell.
  function focusRing() {
    var ring = []
    if (sourceField.visible) ring.push(sourceField.input)
    for (var i = 0; i < presetRepeater.count; i++) {
      var item = presetRepeater.itemAt(i)
      if (item && item.visible && item.enabled) ring.push(item)
    }
    // Custom sits outside the repeater, so it has to be added by hand or the
    // ring runs from the last preset straight into the field it opens.
    if (customButton.visible && customButton.enabled) ring.push(customButton)
    if (promptField.visible) ring.push(promptField.input)
    if (root.result !== "") {
      if (replaceButton.visible) ring.push(replaceButton)
      ring.push(copyButton, againButton)
    }
    return ring
  }

  function moveFocus(step) {
    var ring = focusRing()
    if (ring.length === 0) return
    var at = -1
    for (var i = 0; i < ring.length; i++) if (ring[i].activeFocus) { at = i; break }
    // No focus yet lands on the first entry going forward, the last going back.
    ring[(at + step + ring.length) % ring.length].forceActiveFocus()
  }

  // Alt and a digit runs an action from wherever you are, mid-sentence
  // included. Eight actions is more than anyone wants to walk a Tab ring for
  // the one they use every time, and Alt leaves the digits themselves typable.
  function presetShortcut(event) {
    if (!(event.modifiers & Qt.AltModifier)) return false
    var n = event.key - Qt.Key_1
    if (n < 0 || n > 8) return false
    if (n < root.presets.length) {
      root.ask(root.presets[n].id, "")
      return true
    }
    if (n === root.presets.length) {
      root.toggleCustom()
      return true
    }
    return false
  }

  function presetLabel(id) {
    for (var i = 0; i < presets.length; i++) if (presets[i].id === id) return presets[i].label
    return "Thinking"
  }

  FileView {
    id: promptsFile
    path: root.pluginDir + "prompts.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        root.presets = JSON.parse(text())
      } catch (e) {
        root.presets = []
      }
    }
  }

  FileView {
    id: sessionFile
    path: root.stateDir + "/session.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoadFailed: {
      root.sourceText = ""
      root.sourceKind = ""
    }
    onLoaded: {
      try {
        var session = JSON.parse(text())
        root.sourceText = session.text || ""
        root.sourceKind = session.source || ""
      } catch (e) {
        root.sourceText = ""
      }
    }
  }

  // The bar icon opens straight into an empty field. Reaching for the mouse
  // means your hands already left the text, and clicking a bar icon is not how
  // anyone asks for the sentence they are looking at to be rewritten: that is
  // what SUPER + SHIFT + H is for. `settext ""` is compose without the toggle,
  // which the panel does for itself here.
  Process {
    id: composeProc
    command: [root.cli, "settext", ""]
    onExited: {
      sessionFile.reload()
      root.open()
    }
  }

  Process {
    id: setTextProc
    onExited: function (exitCode) {
      if (exitCode === 0) runProc.running = true
      else root.errorText = "Could not hand the text over (exit " + exitCode + ")"
    }
  }

  Process {
    id: runProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.result = String(text || "").trim()
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.errorText = String(text || "").trim()
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        if (root.errorText === "") root.errorText = "The agent failed with exit code " + exitCode
        root.result = ""
        return
      }
      root.errorText = ""
      if (root.replaceMode && !root.manual && root.result !== "") root.apply()
    }
  }

  Process {
    id: insertProc
    command: [root.cli, "insert"]
  }

  Process {
    id: copyProc
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰁨"
    tooltipText: "OmaPen"
    onPressed: function (b) {
      if (root.opened) root.close()
      else composeProc.running = true
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    // Compose mode opens on its own field, and capture mode opens on the first
    // action, which is the one most likely to be run. Fields own Esc, because
    // the key catcher only sees keys while nothing else has focus.
    focusTarget: root.manual ? sourceField.input
      : (presetRepeater.count > 0 ? presetRepeater.itemAt(0) : customButton)
    contentWidth: popup.fittedContentWidth(Style.space(root.setting("panelWidth", 540)))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      // Tab moves inside the panel rather than between panels: with a text
      // field and ten actions in here, leaving is not what Tab is for.
      onTabRequested: function (direction) {
        root.moveFocus(direction)
      }
      onMoveRequested: function (dx, dy) {
        root.moveFocus(dx + dy > 0 ? 1 : -1)
      }
      // A focused field owns every key, or j and k would move the cursor
      // instead of being typed. Tab and Escape are handled on the fields
      // themselves for that reason.
      blocked: sourceField.editing || promptField.editing

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        PanelHeading {
          width: parent.width
          bar: root.bar
          sourceKind: root.sourceKind
        }

        SourceField {
          id: sourceField
          width: parent.width
          visible: root.manual
          enabled: !root.busy
          bar: root.bar
          panel: root
        }

        Text {
          width: parent.width
          visible: !root.manual && root.sourceText !== ""
          text: root.sourceText
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }

        Text {
          width: parent.width
          visible: !root.manual && root.sourceText === ""
          text: "Nothing to work on. Select some text, then open this again."
          color: Qt.darker(root.bar.foreground, 1.5)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        PanelSeparator {
          width: parent.width
          visible: root.manual || root.sourceText !== ""
        }

        // The actions stay put once there is a result: picking the wrong one is
        // the most likely thing to happen here, and the fix for it should be
        // the same click as the mistake, not closing the panel and starting
        // over. Every action runs against the captured text, never against the
        // result of the last one.
        // Three to a row, all one width: eight shipped actions plus Custom make
        // a square, and a square is quicker to aim at than a ragged wrap.
        Grid {
          id: actionGrid
          width: parent.width
          columns: 3
          spacing: Style.space(6)
          readonly property real cellWidth: (width - spacing * (columns - 1)) / columns
          // Shown from the start in compose mode, disabled until there is
          // something to act on: a panel that grows buttons as you type moves
          // the ones you were aiming for.
          visible: root.manual || root.sourceText !== ""

          Repeater {
            id: presetRepeater
            model: root.presets

            ActionButton {
              required property var modelData
              required property int index
              bar: root.bar
              width: actionGrid.cellWidth
              text: modelData.label
              // The digit is what Alt runs, so it is worth more than a glyph
              // sitting next to a label that already says the same thing. Past
              // the ninth there is no shortcut to advertise, so those keep
              // their icon.
              digit: index < 9 ? String(index + 1) : ""
              iconText: index < 9 ? "" : (modelData.icon || "")
              enabled: !root.busy && root.workingText !== ""
              selected: root.pending === modelData.id && (root.busy || root.result !== "")
              onClicked: root.ask(modelData.id, "")
            }
          }

          ActionButton {
            id: customButton
            bar: root.bar
            width: actionGrid.cellWidth
            text: "Custom"
            digit: root.customDigit
            iconText: root.customDigit !== "" ? "" : "󰏫"
            enabled: !root.busy && root.workingText !== ""
            selected: root.customOpen
            onClicked: root.toggleCustom()
          }
        }

        PromptField {
          id: promptField
          width: parent.width
          visible: root.customOpen
          enabled: root.workingText !== "" && !root.busy
          placeholderText: root.result === "" ? "Or say what to do with it" : "Ask for another pass"
          bar: root.bar
          panel: root
        }

        Text {
          width: parent.width
          visible: root.busy
          text: root.presetLabel(root.pending) + "…"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body

          SequentialAnimation on opacity {
            running: root.busy
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.4; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.4; to: 1.0; duration: 700; easing.type: Easing.InOutSine }
          }
        }

        ResultView {
          width: parent.width
          visible: root.result !== ""
          bar: root.bar
          body: root.result
        }

        Text {
          width: parent.width
          visible: root.errorText !== ""
          text: root.errorText
          color: Color.error !== undefined ? Color.error : root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }

        Row {
          spacing: Style.space(6)
          visible: root.result !== ""

          ActionButton {
            id: replaceButton
            bar: root.bar
            text: "Replace"
            iconText: "󰆐"
            // Compose mode never recorded a window, so there is nowhere to
            // paste back to and Copy is the only sensible exit.
            visible: !root.manual
            onClicked: root.apply()
          }

          ActionButton {
            id: copyButton
            bar: root.bar
            text: "Copy"
            iconText: "󰆏"
            onClicked: {
              copyProc.command = ["wl-copy", "--", root.result]
              copyProc.running = true
              root.close()
            }
          }

          ActionButton {
            id: againButton
            bar: root.bar
            text: "Again"
            iconText: "󰑖"
            onClicked: root.retry()
          }
        }
      }
    }
  }
}
