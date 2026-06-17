# Security

## Reporting a vulnerability

Please report security issues privately via **GitHub Security Advisories**
(repo → Security → *Report a vulnerability*) rather than a public issue. We aim to
acknowledge within a few days.

## Threat model & design notes

MenuMate ships as a **non-sandboxed** Developer ID app plus a **sandboxed** Finder Sync
extension. The security posture follows from that split.

- **Scripts run as you.** Presets, your own actions, and imported pack actions are plain
  `zsh` scripts executed with your user privileges — the same trust level as anything you
  run in Terminal. Only enable actions and packs whose scripts you've read. Scripts are
  invoked via `/bin/zsh "$script" "$@"` with inputs passed as arguments/`MENUMATE_PATHS`;
  MenuMate never `eval`s or string-interpolates selected paths into a command.

- **Extension packs are read-only on import and default-disabled.** Import is a
  `git clone --depth 1` that **never executes anything**. The review step shows every
  manifest-declared script **and every other non-metadata file in the repo** (hidden
  scripts, executables, and binaries are flagged), because a declared script can `source`
  sibling files via `pack_root`. Imported actions are added **disabled** until you enable
  them individually.

- **The App↔extension snapshot is not a privilege boundary.** The app pushes the menu
  config (and, at click time, the right-clicked paths) to the extension over
  `DistributedNotificationCenter`, which is **readable by any process running as the same
  user**. This is acceptable: a same-user process already has equivalent filesystem access
  to the same `config.json` and files. There is no App Group container (that's deliberate —
  it's what avoids the macOS "wants to access data from other apps" prompts). A **forged**
  snapshot can at worst change how the menu *looks* — it can never run a script, because
  every click is re-validated against the local on-disk config: the action id must exist,
  be enabled, and its script path must exist on disk.

- **"Remove Quarantine" is a deliberate Gatekeeper bypass.** If you add an action that
  deletes `com.apple.quarantine`, only run it on files you trust — it removes the macOS
  "downloaded from the internet / unidentified developer" check for those items.

- **Permissions are requested once.** MenuMate asks for Automation (to drive Finder /
  System Events for in-window navigation) and, optionally, Accessibility (to send `⌘↑` in
  non-Finder upload dialogs). It does not require Full Disk Access.

- **The AI-authoring path edits local files directly.** The
  [`menumate-author`](skills/menumate-author/SKILL.md) skill and any external editor write
  `config.json` / `Scripts/` directly, bypassing the pack-review gate. That's intended for
  *your own* automation; treat AI- or script-authored actions with the same scrutiny you'd
  give code you wrote.
