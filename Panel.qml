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

  // Capture runs before the popup exists, never after: the popup takes the
  // keyboard, and the Ctrl+A fallback types into whatever holds it. The
  // keybinding captures on its own and only toggles us afterwards.
  Process {
    id: captureProc
    command: [root.cli, "capture"]
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
      else captureProc.running = true
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
      onTabRequested: function (direction) {
        root.switchPanel(direction)
      }

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
            model: root.presets

            Button {
              required property var modelData
              text: modelData.label
              iconText: modelData.icon || ""
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              bordered: true
              enabled: !root.busy && root.workingText !== ""
              selected: root.pending === modelData.id && (root.busy || root.result !== "")
              onClicked: root.ask(modelData.id, "")
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
            text: "Replace"
            iconText: "󰆐"
            // Compose mode never recorded a window, so there is nowhere to
            // paste back to and Copy is the only sensible exit.
            visible: !root.manual
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.apply()
          }

          Button {
            text: "Copy"
            iconText: "󰆏"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: {
              copyProc.command = ["wl-copy", "--", root.result]
              copyProc.running = true
              root.close()
            }
          }

          Button {
            text: "Again"
            iconText: "󰑖"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.retry()
          }
        }
      }
    }
  }
}
