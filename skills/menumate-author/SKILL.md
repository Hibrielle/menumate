---
name: menumate-author
description: >
  Author MenuMate Finder right-click actions by directly editing its local data
  files. Use when the user wants an AI to add / edit / remove a MenuMate
  right-click action, or implement a Finder capability "in MenuMate". MenuMate
  stores everything as local files and live-reloads them within ~3s, so editing
  the files IS the API — no CLI, no restart.
---

# Authoring MenuMate actions by editing its files

MenuMate (a macOS Finder right-click manager) keeps **all state as plain local files** and
**watches `config.json`'s mtime every ~3s** — so when you edit these files, a running MenuMate
picks up the change automatically (no restart, no import). This skill is how an AI implements a
MenuMate capability for the user.

## Data location

```
~/Library/Application Support/MenuMate/
├── config.json        # the menu: a MenuConfig { schemaVersion, actions: [...] }
├── Scripts/           # zsh scripts referenced by actions (Scripts/foo.sh)
├── Templates/         # files listed by the "New File" submenu
├── Icons/             # imported custom PNG icons (36×36)
└── Packs/             # installed extension packs (don't hand-edit)
```

To add an action: **(1)** drop a zsh script in `Scripts/`, **(2)** append an action object to
`config.json`'s `actions` array. Within ~3s the action appears in Finder's right-click menu.

## The script contract

Scripts run under `/bin/zsh "$SCRIPT" "$@"` (no executable bit needed). Available:

| var / arg | meaning |
|-----------|---------|
| `$1 … $n` | absolute paths of the selected items (the container path for `container` actions) |
| `MENUMATE_PATHS` | all paths, newline-separated |
| `MENUMATE_VARIANT` | the chosen submenu value (when the action has `variants`) |
| `MENUMATE_DATA` / `MENUMATE_TEMPLATES` | the data / templates directories |
| `MENUMATE_SCRIPT` | this script's absolute path → `pack_root="${0:A:h}"` to find sibling files/binaries |
| working dir | the first selected item's folder |
| exit `0` | success; **first stdout line** becomes the success summary |
| exit ≠ `0` | failure; stderr is shown in a notification + "Recent Executions" |

Reference inputs via `"$@"` / `$MENUMATE_PATHS`. **Never** build commands by string-interpolating
paths. Only expand `~` yourself (`${p/#\~/$HOME}`); don't `eval`.

To do heavy work that zsh is bad at, call a tool the user has installed
(`command -v ffmpeg || { print -u2 "需要 ffmpeg: brew install ffmpeg"; exit 1; }`) or a Rust CLI
they `cargo install`ed — keep the script auditable, put the heavy logic in the trusted tool.

## The action object (exact JSON shape)

`config.json` is Swift `Codable` JSON — **enum cases wrap their value in `_0`**. Copy these
templates exactly. A user-authored action omits `presetKey` / `packID` / `packRepo`.

Run a script file (most common):

```json
{
  "id": "<UUID>",
  "title": "Word Count",
  "icon": { "symbol": { "_0": "text.word.spacing" } },
  "kind": { "runScript": { "_0": { "scriptPath": "Scripts/word-count.sh", "timeoutSeconds": 60 } } },
  "matching": { "targets": "files", "utis": [] },
  "placement": "topLevel",
  "isEnabled": true,
  "sortOrder": 100
}
```

Variations:
- **Inline script** (no file): `"kind": { "runScript": { "_0": { "inlineSource": "pbpaste | wc -l", "timeoutSeconds": 60 } } }`
- **Open with an app**: `"kind": { "openWith": { "appBundleID": "com.microsoft.VSCode" } }` (note: labeled value, **no `_0`** here)
- **Submenu (fixed list)**: add `"variants": { "fixed": { "_0": ["png", "jpeg", "heic"] } }` — each value arrives as `$MENUMATE_VARIANT`
- **Submenu (one item per file in a dir)**: `"variants": { "directoryListing": { "_0": "Templates" } }`
- **Custom icon image**: `"icon": { "imageFile": { "_0": "myicon.png" } }` (file must be in `Icons/`)
- **Restrict to a type**: `"matching": { "targets": "files", "utis": ["public.image"] }`

Field reference:
- `id` — any UUID (e.g. `uuidgen`). Must be unique. (Presets use deterministic UUIDs; user actions don't care.)
- `icon.symbol._0` — an SF Symbol name (e.g. `doc.on.doc`, `terminal`, `photo`, `bolt`).
- `matching.targets` — `any` (any selection) · `files` · `folders` · `container` (right-click empty folder background). `container` is mutually exclusive with the other three.
- `matching.utis` — `[]` = no restriction, else UTType list (`public.image`, `public.movie`, `public.text`, `com.adobe.pdf`, …); matches by UTType conformance.
- `placement` — `topLevel` or `submenu` (groups under a "MenuMate ▸" submenu).
- `sortOrder` — integer; use a high value (e.g. 100+) to append at the end.
- `isEnabled` — `true` to show it immediately.

## Recipe: add an action (safe, with `jq`)

```bash
SUPP="$HOME/Library/Application Support/MenuMate"
CFG="$SUPP/config.json"
cp "$CFG" "$CFG.bak"                              # back up first

cat > "$SUPP/Scripts/word-count.sh" <<'SH'
#!/bin/zsh
# Count lines/words/chars of the selected text files; copy a summary to the clipboard.
emulate -L zsh
out=$(wc -lwc "$@" 2>/dev/null | tail -1)
printf '%s' "$out" | pbcopy
print "wc: $out"
SH

ID=$(uuidgen)
jq --arg id "$ID" '.actions += [{
  "id": $id, "title": "Word Count",
  "icon": {"symbol":{"_0":"text.word.spacing"}},
  "kind": {"runScript":{"_0":{"scriptPath":"Scripts/word-count.sh","timeoutSeconds":60}}},
  "matching": {"targets":"files","utis":[]},
  "placement":"topLevel", "isEnabled":true, "sortOrder":100
}]' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
```

MenuMate reloads within ~3s — the action appears in Finder's right-click menu. (If it doesn't,
the JSON was invalid; MenuMate keeps the old config and shows an error — restore `$CFG.bak`,
fix, retry. Always `jq . "$CFG"` to validate before relying on it.)

Edit / remove / toggle: same idea with `jq` (e.g. delete by id
`jq --arg id "$ID" '.actions |= map(select(.id != $id))' …`, or flip `.isEnabled`). Leave
actions with a `packID` to the Packs UI.

## Validate

```bash
jq . "$CFG" >/dev/null && echo "valid JSON"          # must pass
MENUMATE_PATHS="/some/file.txt" /bin/zsh "$SUPP/Scripts/word-count.sh" /some/file.txt  # dry-run the script
```

## Alternative: ship it as an extension pack

For something you want to **share**, author a git-repo extension pack instead (a cleaner
`manifest.json` schema — no `_0` wrappers). See the
[Extension Pack Specification](https://github.com/Hibrielle/menumate/blob/main/docs/pack-spec.md)
and the example packs (`menumate-nav-pack`, `menumate-dev-pack`, `menumate-image-pack`). Tag the
repo `menumate-pack` so it shows up under "Browse community packs".

## Safety

- Back up `config.json` before editing; keep the JSON valid (an invalid file is ignored, not applied).
- Don't simultaneously edit actions in the MenuMate UI while editing files (last writer wins).
- Scripts run with the user's privileges — only write what the user asked for; no network/destructive ops without intent.
