# Releasing MenuMate

MenuMate ships as a **Developer ID-signed, notarized `.dmg`** with **Sparkle** auto-updates.
This document covers the one-time setup and the per-release flow.

> Distribution requires a paid **Apple Developer Program** membership and a **Developer ID
> Application** certificate. An "Apple Development" cert (free) is enough to build and run
> locally, but **not** to notarize for distribution.

---

## One-time setup

### 1. Developer ID certificate

In Xcode → Settings → Accounts, or the Apple Developer portal, create a **Developer ID
Application** certificate and install it in your login keychain. Find its identity string:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
# → "Developer ID Application: Your Name (TEAMID)"
```

### 2. Notarization credentials (App Store Connect API key)

App Store Connect → Users and Access → Integrations → create an **API Key** (role: Developer).
Download the `AuthKey_XXXXXX.p8`. Note the **Key ID** and **Issuer ID**.

For local runs you can instead store a notarytool profile once:

```bash
xcrun notarytool store-credentials menumate-notary \
  --key AuthKey_XXXXXX.p8 --key-id <KEY_ID> --issuer <ISSUER_ID>
# then run releases with NOTARY_PROFILE=menumate-notary
```

### 3. Sparkle EdDSA keys

Generate the signing key pair once (the private key is stored in your login keychain):

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
# prints the PUBLIC key — paste it into project.yml → SUPublicEDKey (replace the placeholder)
```

Export the **private** key for CI (keep it secret):

```bash
build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key.pem
```

After setting `SUPublicEDKey`, re-run `make gen`.

### 4. GitHub Actions secrets

For the tag-triggered [`release.yml`](../.github/workflows/release.yml) workflow, add these
repository secrets (Settings → Secrets and variables → Actions):

| Secret | What |
|--------|------|
| `DEVELOPER_ID_CERT_P12_BASE64` | your Developer ID cert+key exported as `.p12`, then `base64` |
| `DEVELOPER_ID_CERT_PASSWORD` | the `.p12` export password |
| `KEYCHAIN_PASSWORD` | any string (temp CI keychain password) |
| `DEVELOPER_ID_APP` | `Developer ID Application: Your Name (TEAMID)` |
| `TEAM_ID` | your Apple Team ID |
| `NOTARY_KEY_ID` / `NOTARY_ISSUER` | from the API key above |
| `NOTARY_KEY_P8_BASE64` | the `AuthKey_XXXXXX.p8`, `base64`-encoded |
| `SPARKLE_ED_PRIVATE_KEY` | the Sparkle private key string |

Export the cert as base64: `base64 -i DeveloperID.p12 | pbcopy`.

---

## Cutting a release

### Locally

```bash
export DEVELOPER_ID_APP="Developer ID Application: Your Name (TEAMID)"
export TEAM_ID=TEAMID
export NOTARY_PROFILE=menumate-notary        # from step 2
make release VERSION=1.0.0
```

This archives (Release, hardened runtime), exports a Developer ID app, builds a signed dmg,
notarizes + staples it, and prints the Sparkle signature. Artifact: `build/release/MenuMate-1.0.0.dmg`.

### Via CI (recommended)

Bump `CFBundleShortVersionString` / `CFBundleVersion` in `App/Info.plist`, commit, then tag:

```bash
git tag v1.0.0 && git push origin v1.0.0
```

`release.yml` then builds, signs, notarizes, creates a GitHub Release with the dmg, regenerates
`appcast.xml`, and pushes it to `main`. Sparkle clients poll `SUFeedURL`
(`…/main/appcast.xml`) and offer the update.

---

## Checklist

- [ ] `SUPublicEDKey` in `project.yml` is your real Sparkle public key (not the placeholder).
- [ ] Re-enable auto-update: set `SUEnableAutomaticChecks` to `true` (or remove it) in `project.yml` — it's `false` pre-release so dev builds don't pop a "can't check for updates" error on launch.
- [ ] Version bumped in `App/Info.plist`.
- [ ] All nine GitHub secrets set (for CI).
- [ ] `xcrun stapler validate build/release/MenuMate-<v>.dmg` passes.
- [ ] Gatekeeper check on a clean machine: `spctl -a -vvv -t install MenuMate-<v>.dmg`.
