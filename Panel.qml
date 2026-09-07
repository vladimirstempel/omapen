pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

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
  readonly property bool manual: root.sourceKind === "manual"
  readonly property string workingText: root.manual ? sourceInput.text.trim() : root.sourceText

  onOpenedChanged: {
    if (opened) {
      result = ""
      errorText = ""
      freeInput.text = ""
      sourceInput.text = ""
      sessionFile.reload()
    } else if (runProc.running) {
      runProc.running = false
    }
  }

  function ask(presetId, free) {
    if (root.workingText === "") return
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
    } else if (freeInput.text !== "") {
      root.ask("", freeInput.text)
    }
  }

  function retry() {
    if (pending === "-") ask("", freeInput.text)
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
    if (sourceInput.visible) ring.push(sourceInput)
    for (var i = 0; i < presetRepeater.count; i++) {
      var item = presetRepeater.itemAt(i)
      if (item && item.visible && item.enabled) ring.push(item)
    }
    ring.push(freeInput)
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
    if (n < 0 || n >= root.presets.length || n > 8) return false
    root.ask(root.presets[n].id, "")
    return true
  }

  function presetLabel(id) {
    for (var i = 0; i < presets.length; i++) if (presets[i].id === id) return presets[i].label
    return "Thinking"
  }

  // ------------------------------------------------------------------ data

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

  // ------------------------------------------------------------------ bar

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

  // ---------------------------------------------------------------- popup

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    // The prompt field holds the keyboard: open and type, the way the macOS and
    // Chrome versions of this work. It stays visible in every state so focus
    // never has to move, and it owns Esc because the key catcher only sees keys
    // while nothing else has focus.
    focusTarget: root.manual ? sourceInput : freeInput
    contentWidth: popup.fittedContentWidth(Style.space(root.setting("panelWidth", 480)))
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
      blocked: sourceInput.activeFocus || freeInput.activeFocus

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- title ----------
        Item {
          width: parent.width
          implicitHeight: title.implicitHeight

          Text {
            id: title
            text: "OmaPen"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.left: parent.left
          }

          Text {
            text: root.sourceKind === "selection" ? "SELECTION"
                : root.sourceKind === "clipboard" ? "CLIPBOARD"
                : root.sourceKind === "field" ? "WHOLE FIELD"
                : root.sourceKind === "manual" ? "YOUR TEXT" : ""
            color: Qt.darker(root.bar.foreground, 1.6)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.2
            anchors.right: parent.right
            anchors.verticalCenter: title.verticalCenter
          }
        }

        // ---------- what we are working on ----------
        // ponytail: single-line field, the kit ships no multi-line input. Fine
        // for a sentence or a paragraph; swap in a styled TextArea if people
        // start pasting whole documents in here.
        TextField {
          id: sourceInput
          width: parent.width
          visible: root.manual
          enabled: !root.busy
          placeholderText: "Paste or type the text to work on"
          foreground: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          // The key catcher is blocked while this field has focus, so the keys
          // that leave it are handled here.
          Keys.onTabPressed: function (event) { event.accepted = true; root.moveFocus(1) }
          Keys.onBacktabPressed: function (event) { event.accepted = true; root.moveFocus(-1) }
          Keys.onPressed: function (event) { if (root.presetShortcut(event)) event.accepted = true }
          // Return moves on to the instruction rather than doing nothing: type
          // the text, Return, say what to do with it, Return. Swallowing it is
          // required either way, since an unaccepted Return reaches the key
          // catcher, which reads it as "activate" and closes the panel.
          Keys.onReturnPressed: function (event) {
            event.accepted = true
            freeInput.forceActiveFocus()
          }
          Keys.onEnterPressed: function (event) {
            event.accepted = true
            freeInput.forceActiveFocus()
          }
          Keys.onEscapePressed: function (event) {
            event.accepted = true
            root.close()
          }
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

        // ---------- actions ----------
        // The actions stay put once there is a result: picking the wrong one is
        // the most likely thing to happen here, and the fix for it should be
        // the same click as the mistake, not closing the panel and starting
        // over. Every action runs against the captured text, never against the
        // result of the last one.
        Flow {
          width: parent.width
          spacing: Style.space(6)
          // Shown from the start in compose mode, disabled until there is
          // something to act on: a panel that grows buttons as you type moves
          // the ones you were aiming for.
          visible: root.manual || root.sourceText !== ""

          Repeater {
            id: presetRepeater
            model: root.presets

            Button {
              required property var modelData
              required property int index
              text: modelData.label
              // The digit is what Alt runs, so it is worth more than a glyph
              // sitting next to a label that already says the same thing.
              // Past the ninth there is no shortcut to advertise, so those
              // keep their icon.
              iconText: index < 9 ? String(index + 1) : (modelData.icon || "")
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              focusable: true
              enabled: !root.busy && root.workingText !== ""
              selected: root.pending === modelData.id && (root.busy || root.result !== "")
              onClicked: root.ask(modelData.id, "")

              // The kit draws its focus ring in the foreground colour, which on a
              // panel of bordered buttons is nearly invisible. Keyboard users
              // need to see where they are at a glance, so the ring is redrawn
              // in the theme accent.
              Rectangle {
                anchors.fill: parent
                visible: parent.activeFocus
                color: "transparent"
                radius: Style.cornerRadius
                border.width: 2
                border.color: Color.accent
              }
            }
          }
        }

        TextField {
          id: freeInput
          width: parent.width
          enabled: root.workingText !== "" && !root.busy
          placeholderText: root.result === "" ? "Or say what to do with it" : "Ask for another pass"
          foreground: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          // The key catcher is blocked while this field has focus, so the keys
          // that leave it are handled here.
          Keys.onTabPressed: function (event) { event.accepted = true; root.moveFocus(1) }
          Keys.onBacktabPressed: function (event) { event.accepted = true; root.moveFocus(-1) }
          Keys.onPressed: function (event) { if (root.presetShortcut(event)) event.accepted = true }
          // Return has to be swallowed here. Unaccepted it bubbles up to the
          // key catcher, which reads it as "activate" and closes the panel out
          // from under the run that just started.
          // Ctrl+Return applies the result, so the whole thing is reachable
          // from the keyboard: open, type, Return, Ctrl+Return.
          Keys.onReturnPressed: function (event) {
            event.accepted = true
            root.submit(event.modifiers & Qt.ControlModifier)
          }
          Keys.onEnterPressed: function (event) {
            event.accepted = true
            root.submit(event.modifiers & Qt.ControlModifier)
          }
          Keys.onEscapePressed: function (event) {
            event.accepted = true
            root.close()
          }
        }

        // ---------- thinking ----------
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

        // ---------- result ----------
        Flickable {
          width: parent.width
          visible: root.result !== ""
          implicitHeight: Math.min(resultText.implicitHeight, Style.space(260))
          contentHeight: resultText.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Text {
            id: resultText
            width: parent.width
            text: root.result
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
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

          Button {
            id: replaceButton
            text: "Replace"
            iconText: "󰆐"
            // Compose mode never recorded a window, so there is nowhere to
            // paste back to and Copy is the only sensible exit.
            visible: !root.manual
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            focusable: true
            onClicked: root.apply()

            // The kit draws its focus ring in the foreground colour, which on a
            // panel of bordered buttons is nearly invisible. Keyboard users
            // need to see where they are at a glance, so the ring is redrawn
            // in the theme accent.
            Rectangle {
              anchors.fill: parent
              visible: parent.activeFocus
              color: "transparent"
              radius: Style.cornerRadius
              border.width: 2
              border.color: Color.accent
            }
          }

          Button {
            id: copyButton
            text: "Copy"
            iconText: "󰆏"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            focusable: true
            onClicked: {
              copyProc.command = ["wl-copy", "--", root.result]
              copyProc.running = true
              root.close()
            }

            // The kit draws its focus ring in the foreground colour, which on a
            // panel of bordered buttons is nearly invisible. Keyboard users
            // need to see where they are at a glance, so the ring is redrawn
            // in the theme accent.
            Rectangle {
              anchors.fill: parent
              visible: parent.activeFocus
              color: "transparent"
              radius: Style.cornerRadius
              border.width: 2
              border.color: Color.accent
            }
          }

          Button {
            id: againButton
            text: "Again"
            iconText: "󰑖"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            focusable: true
            onClicked: root.retry()

            // The kit draws its focus ring in the foreground colour, which on a
            // panel of bordered buttons is nearly invisible. Keyboard users
            // need to see where they are at a glance, so the ring is redrawn
            // in the theme accent.
            Rectangle {
              anchors.fill: parent
              visible: parent.activeFocus
              color: "transparent"
              radius: Style.cornerRadius
              border.width: 2
              border.color: Color.accent
            }
          }
        }
      }
    }
  }
}
