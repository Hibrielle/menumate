# MenuMate Example Pack

A reference [extension pack](../../docs/pack-spec.md) for MenuMate. Fork it as a starting
point for your own.

It defines three actions that show off the manifest features:

| Action | `targets` / `utis` | Demonstrates |
|--------|--------------------|--------------|
| Copy file name (no extension) | `files` | positional args, `pbcopy`, stdout summary |
| Total size of selection | `any` | reading `$@`, shelling out, first-line summary |
| Convert image to… | `files`, `public.image` | a submenu (`variants.fixed`) via `$MENUMATE_VARIANT` |

## Try it

1. Push this folder (or a fork) to its **own** GitHub repo — `manifest.json` must be at the
   repo root.
2. In MenuMate → **Extension Packs** → **Import**, paste `owner/repo`.
3. Review each script, confirm, then enable the actions you want.

## Make yours discoverable

Add the GitHub topic `menumate-pack` to your repository so it shows up under
“Browse community packs”.
