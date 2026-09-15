# MenuMate Extension Pack Specification

English · [简体中文](pack-spec.zh.md)

An **extension pack** is just a git repository with a `manifest.json` at its root. Anyone
can publish one; users import it by URL. MenuMate clones it for review, shows you every
script, and only adds its actions **disabled** — you enable each one after reviewing it.

A reference pack lives in [`examples/example-pack/`](../examples/example-pack/).
For two actions with separate HTML windows in one pack, see
[`examples/image-tools-pack/`](../examples/image-tools-pack/). Run
`zsh scripts/prepare-image-tools-pack.sh` from the project root to create a local
Git repository, then paste its printed path into **Extension Packs → Import**.
Each action can be enabled independently; installation, updates, and uninstallation
apply to the whole pack. Subdirectories are not independently installable packs.

---

New to pack development? Start with the [development guide](extension-development.md) and [starter pack](../examples/selection-info-pack/). This document is the field and protocol reference.


## Repository layout

```
your-pack/
├── manifest.json          # required, at the repo root
└── actions/               # your script files (any layout; referenced by manifest)
    ├── foo.zsh
    └── bar.zsh
```

Import sources accepted by MenuMate:

- `owner/repo` shorthand → expands to `https://github.com/owner/repo.git`
- a full `https://…` or `git@…` git URL

---

## `manifest.json`

```jsonc
{
  "schemaVersion": 1,              // optional, default 1; a pack declaring > current is rejected
  "name": "Dev Tools",            // required, non-empty — shown as the pack name
  "author": "Li Hua",             // optional, display only
  "description": "Handy actions", // optional, display only
  "icon": "hammer",               // optional SF Symbol, default "shippingbox"
  "actions": [                     // required, non-empty
    {
      "id": "copy-basename",      // required, non-empty, unique within the pack — STABLE id
      "title": "Copy file name",  // required, non-empty — the context-menu label
      "icon": "doc.on.doc",       // optional SF Symbol, default "bolt"
      "script": "actions/copy-basename.zsh",  // required, safe relative path
      "targets": "files",         // optional: files | folders | any | container (default any)
      "utis": ["public.image"],   // optional UTI filter (default []), UTType conformance match
      "placement": "topLevel",    // optional: topLevel | submenu (default topLevel)
      "variants": { "fixed": ["png", "jpeg"] },  // optional submenu; see below
      "timeoutSeconds": 60        // optional, default 60
    }
  ]
}
```

Unknown fields are ignored (forward-compatible). All optional fields fall back to the
defaults above.

### Translated names and descriptions

Keep the required `name` and action `title` as fallback text. Add optional language maps:

```json
{
  "schemaVersion": 1,
  "name": "Image Tools",
  "localizedNames": {"en": "Image Tools", "zh-Hans": "图片工具"},
  "description": "Image utilities",
  "localizedDescriptions": {"en": "Image utilities", "zh-Hans": "图片处理工具"},
  "actions": [{
    "id": "convert", "title": "Convert image", "script": "convert.zsh",
    "localizedTitles": {"en": "Convert image", "zh-Hans": "图片转换"}
  }]
}
```

These optional metadata fields work in schema 1 and 2; old clients keep using fallback
text. Exact language tags take priority, followed by broader language/script matches
(e.g. `en-US` → `en`, `zh-CN` → `zh-Hans`). Missing or blank translations use fallback
text; Simplified Chinese is not automatically substituted for Traditional Chinese.
The app passes its language to Finder through the snapshot. Action IDs, script paths
and submenu values do not change with language. Fixed submenu values are still displayed
as authored. Execution history stores the name displayed at execution time.

Local users can edit English and Simplified Chinese action names in **Localized names**.
Pack updates merge translations per language, preserving user edits and explicitly cleared
translations. Other locale tags can be authored in the manifest/config JSON.

### `id` — keep it stable

The `id` is how MenuMate matches actions across updates to **preserve the enabled state**
the user set. Renaming an `id` makes it a different action (the old one disappears, the new
one arrives disabled). Choose stable, kebab-case ids and don't change them.

### `script` — must be a safe relative path

Validated by `isSafeRelativeScriptPath`: must be non-empty, must **not** start with `/`
(no absolute paths), and **no path segment may be `..`** (no escaping the repo). The file
must actually exist in the repo at that path.

### `targets`

| value | shows when the user right-clicks… | mutually exclusive with |
|-------|-----------------------------------|--------------------------|
| `files` | one or more files selected (no folders) | `container` |
| `folders` | one or more folders selected | `container` |
| `any` | any selection (files and/or folders) | `container` |
| `container` | empty space inside a folder (no selection) | the three above |

`container` and the selection kinds never appear together — pick the one that fits.

### `utis`

A list of Uniform Type Identifiers. An action shows only if **every** selected item
conforms (UTType conformance, not string equality) to **at least one** of them. Empty = no
restriction. Common values: `public.image`, `public.movie`, `public.audio`, `com.adobe.pdf`,
`public.text`, `public.source-code`, `public.archive`.

### `variants` — submenus

Expands one action into a submenu; the chosen value is passed to the script via
`$MENUMATE_VARIANT`.

- `{ "fixed": ["png", "jpeg", "webp"] }` — a fixed list of submenu items.
- `{ "directoryListing": "SomeDir" }` — one item per file in `SomeDir` (relative to the
  MenuMate data directory). If the directory is empty, the whole action is hidden.

Omit `variants` for a normal (non-submenu) action.

---

## Script environment contract

Pack scripts run exactly like built-in presets — under `/bin/zsh`, no executable bit needed:

| variable / arg | meaning |
|----------------|---------|
| `$1 … $n` | absolute paths of the selected items (the container path for `container` actions) |
| `MENUMATE_PATHS` | all paths, newline-separated (handy for loops) |
| `MENUMATE_VARIANT` | the chosen submenu value (empty when there is no submenu) |
| `MENUMATE_DATA` | absolute path to MenuMate's data directory (persist state here) |
| `MENUMATE_TEMPLATES` | absolute path to the templates directory |
| `MENUMATE_SCRIPT` | this script's own absolute path; `pack_root="${0:A:h}"` locates sibling files/binaries shipped in the pack |
| working directory | the first selected item's folder |
| exit `0` | success; the first stdout line becomes the success summary |
| exit non-`0` | failure; stderr is surfaced in “Recent Executions” and a notification |

Reference the input via `"$@"` / `$MENUMATE_PATHS`; never build shell commands by string
interpolation of paths.

---

## How import works (and why it's safe)

1. **Clone** — `git clone --depth 1` into a temp dir. **No script is executed** at any point
   during import.
2. **Review** — MenuMate shows every script read-only; you must open each one before you can
   continue.
3. **Confirm** — the pack is moved to `…/Application Support/MenuMate/Packs/<key>/`, and its
   actions are added to your config **disabled**, tagged with the pack id, their `script`
   resolved to the on-disk absolute path. You enable each action individually.

Scripts are read-only clones. To change a pack's script, fork the repo and re-import.

### Updates

“Check for updates” compares the remote `HEAD` SHA to the installed one. An update clones the
new version, shows a per-file diff (added / removed / modified) and any new actions (which
arrive disabled), and only applies after you confirm. Review covers the whole pack except
its root `.git` metadata, including JS/CSS dependencies, the manifest, hidden files,
file permissions, and symlink targets. Binary files and text over 256 KiB show their size
and SHA-256 instead of full contents. Unreadable or oversized reviews fail explicitly
(at most 10,000 entries and 32 MiB of preview data per tree).
Enabled state and order are preserved per action `id`; custom titles and placement
are retained when they differ from the previous manifest. Untouched fields adopt the
new upstream defaults. Actions removed upstream disappear. Re-importing an installed
pack is rejected with a prompt to use Check for Updates; it does not create duplicates.

---

## Publishing & discovery

Any conforming public git repo is importable by URL — no registry, no submission. To make a
pack discoverable, add the GitHub **topic** `menumate-pack` to your repository; MenuMate's
“Browse community packs” opens that topic search.

**Security note for authors and users:** pack scripts run with the user's privileges. Keep
scripts auditable and dependency-free; users should review every script before enabling it and
never import packs from untrusted sources.

## Interactive actions (schema version 2)

Script-only packs continue to use schema version 1, including when `schemaVersion` is
omitted. Interactive packs must explicitly declare version 2. To show a local webpage when an
action is clicked, set `schemaVersion` to `2` and add an optional interface:

```json
{
  "schemaVersion": 2,
  "name": "Image Tools",
  "actions": [{
    "id": "compress",
    "title": "Compress JPEG",
    "script": "compress.zsh",
    "targets": "files",
    "utis": ["public.jpeg"],
    "interface": {"entry": "ui/index.html", "width": 500, "height": 600}
  }]
}
```

The page and its assets must be local to the pack. Keep resources alongside the HTML
entry or in its subdirectories: WebView file access is limited to the entry directory. The HTML entry is shown alongside
the script during import review; additional files remain in the extra-file review.
Updates compare all pack files, including referenced JavaScript and other resources;
opening a file is not a security certification.
Remote resources and navigation away from the entry page are blocked by the host.

At document start, the host provides `window.menumate`:

```js
const {files, parameters, variant, isTestRun, locale} = window.menumate.context;
// locale: the app UI language (currently en or zh-Hans); localize the page accordingly.
// files: [{name, path}], captured when this window opens.
// parameters: options remembered by this action on a previous real submission.
window.menumate.submit({quality: 80, maxEdge: 1920}, true);
// The second argument requests remembering these options (ignored for test runs).
window.menumate.cancel();
window.addEventListener("menumate:result", ({detail}) => {
  // detail: {exitCode, stdout, stderr, timedOut}
});
```

Put `submit` inside the page's explicit action button handler. The host accepts at
most one submission per window. Parameters must be a JSON object of at most 64 KB.
The host passes the encoded object to the existing script in `MENUMATE_INPUT`;
scripts must parse and validate their own parameters, not evaluate them as commands.
Cancel before submission does not execute the script or remember draft options.
While execution is running, the native window stays open until the script exits or
times out. The page cannot choose another action or replace the selected file list.

Custom local actions can attach an HTML file under **Execution settings**.
**More → Add interactive image action** creates a disabled, editable JPEG example.
Use its test button before enabling it in Finder.

## Testing with generated resources

The test button creates a fresh directory under
`~/Library/Application Support/MenuMate/TestRuns/<UUID>/`.
It generates matching resources in `Inputs/`, plus independent `Data/` and `Templates/`
folders, and passes those directories through the normal script environment.
Scripts receive the app language through `MENUMATE_LOCALE`.
The test run also receives `MENUMATE_TEST_RUN=1` and `MENUMATE_TEST_ROOT`.
Generated outputs remain available through **Open folder**. Unsupported formats and
unsatisfied selection rules fail explicitly instead of generating misleading empty files.
Directory-based submenus can use generated samples only for the standard `Templates`
directory. Other configured directories are explicitly unsupported in trial runs;
they are not silently replaced with generic templates and no user files are copied.

This is a disposable-data workflow, **not a process sandbox**. Scripts retain the user's
permissions, and hardcoded paths, clipboard operations or application automation can
still affect the real environment. The tested script is the actual configured script;
it is not rewritten to redirect arbitrary filesystem operations.

### Interrupted installation and recovery

Import, update and uninstall journal the pack directory, `installed.json` and `config.json`.
Pre-commit failures restore the old state. Startup recovers interrupted operations before
publishing actions; a saved commit marker distinguishes rollback from cleanup. Corrupt
recovery records are preserved and block further writes until repaired. Open HTML dialogs
and queued/running pack actions block update and uninstall. Reviewed updates are rejected
if the installed revision changed before applying them.
