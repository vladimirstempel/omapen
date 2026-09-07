# OmaPen

Rewrite whatever text you have selected, without leaving the window you are in.
The Chrome and macOS feature, on Omarchy, using the coding agent Omarchy already
knows about instead of an API key. Text that is not selected anywhere works
too: open the panel empty and type into it.

Select some text, press `SUPER + SHIFT + H`, pick an action or type your own.
The result comes back in a panel you can paste, or straight over the selection.
Keyboard the whole way: open, type, Return to run, Ctrl+Return to paste it back.

Nothing selected? `SUPER + CTRL + SHIFT + H` opens the same panel with an empty
field to type or paste into, for text that is not on the screen yet. That one
captures nothing, so it works while a terminal is focused too.

![The OmaPen panel: the captured sentence, the eight presets, a free prompt
field, and the rewrite with Replace, Copy and Again](preview.webp)

## Requirements

- Omarchy 4 (the Quickshell `omarchy-shell`, plugin schema 1)
- A default agent: `omarchy default agent claude` (or codex, gemini, opencode, crush, copilot)
- `jq`, `wl-clipboard`, `wtype`, all of which Omarchy already installs

## Install

```bash
omarchy plugin add https://github.com/vladimirstempel/omapen.git --enable --yes
```

That clones into `~/.config/omarchy/plugins/omapen` and puts the icon in the bar.
If you already have the repo checked out somewhere and symlinked into that
folder, `add` refuses the clone rather than overwriting it: the checkout is
already the installed plugin, so skip this step and just enable it with
`omarchy plugin enable omapen`.

Then add the keybinding to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + H", "OmaPen", "$HOME/.config/omarchy/plugins/omapen/bin/omapen open")
o.bind("SUPER + CTRL + SHIFT + H", "OmaPen compose", "$HOME/.config/omarchy/plugins/omapen/bin/omapen compose")
```

The second one opens the panel with an empty page to type or paste into, for
text that is not selected anywhere. See [Bring your own text](#bring-your-own-text).

And, if you want it in the Omarchy menu, one row in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"omapen": {"icon":"󰁨","label":"OmaPen","description":"Rewrite the selected text with the system agent","action":"$HOME/.config/omarchy/plugins/omapen/bin/omapen open"},
```

The bar icon is placed on the right by default. Move it with
`omarchy bar move omapen`.

## Uninstall

```bash
omarchy plugin remove omapen
```

That unloads the widget from the running shell, takes it out of the bar and
deletes `~/.config/omarchy/plugins/omapen`. Three things it does not touch,
because it did not create them:

```bash
# the keybinding line you added
$EDITOR ~/.config/hypr/bindings.lua

# the menu row, if you added one
$EDITOR ~/.config/omarchy/extensions/omarchy-menu.jsonc

# your own presets, if you made any
rm -rf ~/.config/omapen
```

Nothing else is left behind: the session file and the last result live in
`$XDG_RUNTIME_DIR/omapen`, which the system clears on logout.

## Where the text comes from

1. Whatever the focused window copies on Ctrl+C right now. This is the live
   selection, and asking the window beats reading the primary selection, which
   holds on to whatever you last selected anywhere, however long ago.
2. The whole focused field, via Ctrl+A Ctrl+C, when nothing is selected there.
3. The primary selection, for windows that are off limits to keystrokes.
4. The clipboard, last of all.

Terminals never get keystrokes: Ctrl+C there stops the running command. In a
terminal the panel falls back to the selection and the clipboard. Turn "Read the
focused window" off to get that behaviour everywhere.

A page with nothing selected has no field to read, so step 2 copies the whole
page. The preview at the top of the panel is there to catch that before you run
anything.

Wayland has no way to add an item to another application's context menu, so the
keybinding is the equivalent: it works in every window, including the ones that
have no menu at all.

## Bring your own text

`SUPER + CTRL + SHIFT + H` opens the panel with nothing captured and the cursor
in an empty field. Paste something from your phone, or type the sentence you
are about to write, and the same actions apply to it. The badge reads
`YOUR TEXT` so it is never in doubt which one you are in.

Type the text, press Return to move to the instruction, Return again to run.
No keystrokes are sent to any window for this, which is also why it is the one
that works while a terminal is focused, where capture refuses to press keys.

There is no window behind it to paste back into, so `Replace` is not offered
here and `Copy` is the way out.

## Settings

Settings live inline on the widget's entry in `~/.config/omarchy/shell.json`.
Edit them there, or with the bar CLI, which writes the same place:

```bash
omarchy bar set omapen model haiku      # or opus, sonnet, a full model id
omarchy bar set omapen agent codex      # override the system default agent
omarchy bar set omapen resultMode "Replace the selection"
omarchy bar set omapen model ""         # back to the small fast default
```

| Setting | Default | What it does |
|---|---|---|
| Agent | System default | Follows `omarchy default agent`, or names one to use instead. |
| Model | empty | Passed to the agent as its model flag. Empty picks a small fast model per agent: `haiku` for claude, `gpt-5.6-luna` at minimal reasoning for codex, `gemini-3.7-flash` for gemini. Agents whose model ids depend on your own provider config (opencode, copilot, crush) keep their own default. |
| What to do with the result | Show in panel | Or replace the selection: focuses the window the text came from and pastes over it. |
| Grab the whole field | on | The Ctrl+A Ctrl+C fallback described above. |
| Panel width | 480 | In the shell's spacing units. |

## Your own actions

The shipped actions live in `prompts.json`. Copy it to
`~/.config/omapen/prompts.json` and that file wins. Each entry needs an
`id`, a `label`, an optional Nerd Font `icon`, and the `instruction` the agent
is given.

## How it works

The QML side draws. Everything that touches the clipboard, the compositor or the
agent is in `bin/omapen`, which runs on its own from a terminal:

```bash
bin/omapen capture              # selection -> $XDG_RUNTIME_DIR/omapen/session.json
bin/omapen compose              # empty session, nothing captured
bin/omapen run shorten          # ask the agent, print the result
bin/omapen run - "make it rhyme"
bin/omapen insert               # paste the last result back where it came from
bin/omapen insert -             # or paste whatever is piped in
bin/omapen selftest             # the whole chain against a fake agent, no tokens spent
```

The agent runs headless in an empty temporary directory, so no project
`CLAUDE.md`, repository or MCP server from wherever the shell happens to be
running leaks into a rewrite.

## Development

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/omapen
omarchy-shell shell rescanPlugins
omarchy plugin enable omapen
```

Omarchy hot reloads plugin code on save, but its watcher does not follow a
symlinked plugin directory, so an out-of-tree checkout needs
`omarchy-restart-shell` after each edit. A checkout that lives in
`~/.config/omarchy/plugins/omapen` for real reloads on save.

`bin/omapen selftest` covers the prompt building, the agent command table, the
settings reader, the compose session and the run path. The compositor parts (focus, paste, the
Ctrl+A fallback) need a session and are checked by hand.

## License

MIT, see [LICENSE](LICENSE).

The plugin ships no bundled dependencies. It shells out to `jq`,
`wl-clipboard`, `wtype` and `hyprctl`, all of which Omarchy already installs,
and to whichever coding agent you have set up. Nothing is vendored and nothing
is downloaded at runtime.
