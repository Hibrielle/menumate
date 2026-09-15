# Developing MenuMate extension packs

English · [简体中文](extension-development.zh.md) · [Back to README](../README.md)

A pack is a Git repository with a root `manifest.json` and one or more context-menu actions.
Each action runs a zsh script. Add a local HTML dialog when users need to choose parameters;
no changes to MenuMate or app recompilation are required.

Start with the [copyable starter pack](../examples/selection-info-pack/). **List file names**
runs directly; **Selected file info** opens a dialog, lets you choose names or full paths,
and displays the result. Neither action modifies files.

Jump to: [Quick start](#run-the-starter) · [Manifest](#define-actions-and-matching-rules) · [HTML interaction](#add-an-html-dialog) · [Script parameters](#read-parameters-in-the-script) · [Debug and publish](#debug-and-publish)

## Run the starter

Run these commands from the **MenuMate source repository root** on macOS, with Git installed.

1. Copy the example into a separate Git repository:

   ```sh
   pack_dir=$(mktemp -d "${TMPDIR:-/tmp}/menumate-starter.XXXXXX")
   cp -R examples/selection-info-pack/. "$pack_dir/"
   git -C "$pack_dir" init
   git -C "$pack_dir" add .
   git -C "$pack_dir" commit -m "Create MenuMate extension pack"
   printf '%s\n' "$pack_dir"
   ```

   If Git requests an author identity, configure your own `user.name` and `user.email`
   in this new repository, then commit again. Copy the printed directory path.

2. In MenuMate, choose **Packs → Import Pack**, paste that path, inspect the source and
   confirm. Import clones committed content; uncommitted working-tree edits are not installed.
3. In **Context Menu**, search for **Selected file info**, choose **Test Run**, select a
   supported sample and run it. Choose **Full paths** in the HTML dialog, then **Run**.
   The result should contain the sample paths. Test runs work before enabling the action.
4. Enable the actions in **Packs**, then select files in Finder and right-click. The direct
   action's output is available in **Recent Executions** from the menu-bar icon; the HTML
   action also displays its output in the dialog.
5. Edit the source repository, commit the changes, then check for updates in MenuMate,
   review the diff and apply. Do not edit the installed clone or re-import to update it.
   The starter above lives in a temporary directory; use your own project directory for
   ongoing development.

```text
selection-info-pack/
├── manifest.json
├── actions/
│   ├── names.zsh       # Runs directly
│   └── report.zsh      # Reads HTML parameters
└── ui/
    └── report.html     # Collects options and displays results
```

## Define actions and matching rules

A script-only pack can start with this manifest:

```json
{
  "schemaVersion": 1,
  "name": "My File Tools",
  "actions": [{
    "id": "list-names",
    "title": "List file names",
    "icon": "list.bullet",
    "script": "actions/names.zsh",
    "targets": "files",
    "placement": "topLevel",
    "timeoutSeconds": 30
  }]
}
```

`actions/names.zsh`:

```zsh
#!/bin/zsh
emulate -L zsh
set -euo pipefail
for item in "$@"; do
  print -r -- "${item:t}"
done
```

MenuMate invokes `/bin/zsh`, so the file does not need `chmod +x`. Selected paths are separate
positional arguments: iterate over `"$@"`. `${item:t}` is zsh's filename modifier. Do not
concatenate paths into commands or pass them to `eval`.

| Requirement | Manifest setting |
| --- | --- |
| Files, folders, or both | `targets`: `files`, `folders`, or `any` |
| Right-click a folder's empty area | `targets: "container"`; the script receives the container path |
| Images or JPEG only | `utis: ["public.image"]` or `["public.jpeg"]`; every selected item must match |
| Place an action inside the MenuMate group | `placement: "submenu"`; use `topLevel` for the top level |
| Give an action its own choices | `variants: {"fixed": ["png", "jpeg"]}`; the choice arrives in `MENUMATE_VARIANT` |

`placement` controls where the action lives; `variants` controls whether it has child items.
Keep action `id` values stable. Renaming a title preserves identity; changing an ID removes
the old action and introduces a new one. Script and HTML entry paths are relative to the
pack root; absolute paths and `..` segments are rejected.

See the [pack specification](pack-spec.md) for all fields, defaults and directory-based submenus.

## Add an HTML dialog

Set the manifest's `schemaVersion` to **2**, keep the action's `script`, and add `interface`:

```json
{
  "id": "selection-report",
  "title": "Selected file info",
  "script": "actions/report.zsh",
  "targets": "files",
  "interface": {"entry": "ui/report.html", "width": 500, "height": 480}
}
```

Schema 2 packs may mix direct and HTML actions. Remote page URLs are not supported. The entry
must be a local `.html` or `.htm` file no larger than 1 MiB. Width is clamped to 360–900 and
height to 320–900.

```text
Finder click → HTML opens with selected files → user chooses options
→ submit(JSON) → zsh reads MENUMATE_INPUT → result event returns to HTML
```

HTML owns the form and result display. The script performs file operations. The WebView
provides no Node.js, shell or general filesystem API; receiving a path does not grant the
page access to that file's contents.

### Read the context

The host injects `window.menumate` before page scripts run. No SDK installation is needed:

```js
const bridge = window.menumate;
const ctx = bridge.context;
document.querySelector('#files').textContent =
  ctx.files.map(file => file.name).join('\n');
```

| Field | Type and purpose |
| --- | --- |
| `files` | `[{name, path}]`, the captured selection; paths are absolute |
| `title` / `locale` | Current display title and app language, such as `en` or `zh-Hans` |
| `parameters` | Previously remembered parameters; `{}` on first use and for test runs |
| `variant` / `runID` | Submenu choice (empty string when absent) and window session ID |
| `isTestRun` / `testRoot` | Test-run flag and sample root; ordinary runs have an empty `testRoot` |

Opening the HTML in a regular browser does not provide the bridge. The starter displays an
explanation and disables execution there; use this for layout previews and MenuMate for execution.

### Submit, receive results and close

This snippet assumes elements named `#run`, `#close`, `#mode`, `#remember`, and `#result`.
Use the [complete HTML](../examples/selection-info-pack/ui/report.html) as a runnable starting point.

```js
document.querySelector('#run').addEventListener('click', () => {
  const mode = document.querySelector('#mode').value;
  document.querySelector('#run').disabled = true;
  bridge.submit({mode}, document.querySelector('#remember').checked);
});
window.addEventListener('menumate:result', ({detail}) => {
  const {exitCode, stdout, stderr, timedOut} = detail;
  document.querySelector('#result').textContent =
    [timedOut ? 'Timed out' : `Exit code ${exitCode}`, stdout, stderr].join('\n');
});
document.querySelector('#close').addEventListener('click', () => bridge.cancel());
```

`submit(parameters, remember = false)` sends a JSON object and **does not return a Promise**.
The root cannot be an array, string or `null`; the encoded payload is limited to 65,536 bytes.
Send business options, not shell commands or an action ID to execute. A window accepts one
submission only; reopen the action for another run instead of calling `submit()` again.

When the host accepts a submission with `remember: true`, it stores the parameters before
execution. A subsequent script failure therefore does not discard that choice. Preferences
are per action, not per file; cancellation and test runs do not save them.

`menumate:result` fires once when execution finishes, not as a stream. Each of `stdout` and
`stderr` contains at most its first 32,000 characters. Render with `textContent`. If the host
rejects invalid parameters before execution, it shows a native error without producing a
script-result event; validate your form before submitting.

`cancel()` closes the dialog before submission or after completion. While a script runs,
closing is ignored and `cancel()` does not terminate it. Set the execution limit with
`timeoutSeconds`.

## Read parameters in the script

The starter uses macOS's built-in `plutil`; Python, Node.js and jq are not required:

```zsh
mode=$(print -rn -- "${MENUMATE_INPUT:-}" |
  /usr/bin/plutil -extract mode raw -expect string -o - - 2>/dev/null) || {
  print -u2 -- 'Expected a string mode'; exit 2
}
[[ "$mode" == names || "$mode" == paths ]] || {
  print -u2 -- 'mode must be names or paths'; exit 2
}
for item in "$@"; do
  if [[ "$mode" == names ]]; then print -r -- "${item:t}"
  else print -r -- "$item"
  fi
done
```

See [report.zsh](../examples/selection-info-pack/actions/report.zsh). Validate again in the
script: remembered values may come from an older version. Check numeric types/ranges and
enumerated values, and use argument arrays when invoking tools.

Direct actions receive `{}` in `MENUMATE_INPUT`; HTML actions receive the submitted JSON.
Use `${0:A:h}` to locate resources beside the script. The working directory depends on the
selection, not the pack location. See the [script environment contract](pack-spec.md#script-environment-contract)
for data, templates, locale and tool preferences. stdin is closed; collect interactive input
through HTML or environment variables instead.

## Resources, dependencies and localization

Place CSS, JS and images beside the HTML entry or in its subdirectories, using relative
references. HTTP(S) resources and WebSockets are blocked, so bundle dependencies instead of
using a CDN. Navigation, iframes and new windows are not supported interaction mechanisms;
implement multi-step forms inside one page.

A script can perform network-dependent work; document the services, transmitted data and
credentials it needs. MenuMate does not install runtime dependencies or manage secrets.
Prefer existing system tools, and check any required dependencies at script startup with a
clear failure message.

Use `localizedNames`, `localizedDescriptions` and `localizedTitles` for pack names,
descriptions and action titles. For example, on an action:

```json
"localizedTitles": {"en": "Selected file info", "zh-Hans": "所选文件信息"}
```

HTML translates its own form using `context.locale`; scripts can use `MENUMATE_LOCALE` for
output. Required `name` and `title` remain the fallback text. Fixed submenu values are not
automatically translated.

## Debug and publish

Test parameter handling in Terminal first, reusing `pack_dir` from the setup above:

```sh
/bin/zsh "$pack_dir/actions/names.zsh" "$pack_dir/manifest.json"
MENUMATE_INPUT='{"mode":"paths"}' /bin/zsh \
  "$pack_dir/actions/report.zsh" "$pack_dir/manifest.json"
```

The first command should print `manifest.json`; the second its full path. An unsupported
`mode` should return a nonzero exit code. Then test in the app with multiple files, spaces
in names, timeouts, cancellation, remembered options and both languages. Generated trials
use separate sample directories but scripts still have the user's permissions; this is not
a process sandbox.

| Symptom | Check |
| --- | --- |
| Missing Finder action | Enabled state, Finder extension, supported location, and matching `targets` / `utis` |
| Blank HTML or missing styles | Schema 2, existing entry, local resource directory, remote resources or navigation |
| Clicking produces no result | Form validation, payload size, native error message, and whether this window already submitted |
| Missing command or companion file | Runtime dependencies, PATH, and script-relative resource paths |
| Installed version did not change | Commit source changes, check/review updates, close pack dialogs and wait for actions to finish |

Publish committed pack files at the root of a separate repository. Users can then import
its address. Add the GitHub topic `menumate-pack` for community discovery. One repository is
one pack: actions can be enabled independently, while updates/uninstall affect the whole
pack. Repository subdirectory installation, automatic dependency installation and per-action
version updates are not supported.

Continue with the [full specification](pack-spec.md), [script/submenu examples](../examples/example-pack/)
and [image compression/conversion HTML examples](../examples/image-tools-pack/).
