# MenuMate Extension Pack Specification

An **extension pack** is just a git repository with a `manifest.json` at its root. Anyone
can publish one; users import it by URL. MenuMate clones it read-only, shows you every
script, and only adds its actions **disabled** — you enable each one after reviewing it.

A reference pack lives in [`examples/example-pack/`](../examples/example-pack/).

---

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
arrive disabled), and only applies after you confirm. Enabled state is preserved per action
`id`; actions removed upstream disappear.

---

## Publishing & discovery

Any conforming public git repo is importable by URL — no registry, no submission. To make a
pack discoverable, add the GitHub **topic** `menumate-pack` to your repository; MenuMate's
“Browse community packs” opens that topic search.

**Security note for authors and users:** pack scripts run with the user's privileges. Keep
scripts auditable and dependency-free; users should review every script before enabling it and
never import packs from untrusted sources.
