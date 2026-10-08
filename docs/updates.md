# Development updates with Sparkle

Arkiv uses **Sparkle 2.10.0**, pinned through its official binary Swift Package
Manager package. macOS 13+, Intel and Apple Silicon remain supported. The app
embeds the complete Universal framework and its helpers, preserving symlinks,
signs nested code inside-out, and tests loading it from the actual packaged app.
The original icon, engine, Finder Services and DMG workflow are unchanged.

## Trust and behavior

**Arkiv → Check for Updates…** uses `SPUStandardUpdaterController`: native version
and release information, secure download, verification, installation and relaunch.
On second launch Sparkle asks permission for background checks. **Automatically
Check for Updates** changes that preference later. Download/install is always
user-confirmed for this development channel; unattended installation is disabled.
Finish or cancel archive operations before installing; Arkiv's existing termination
veto remains in place while operations are running.

Both ZIP and appcast are Ed25519/EdDSA-signed. The app requires verification before
extraction and signed feeds, with no timeout fallback to accepting unsigned feeds.
The feed and payload use HTTPS. No custom installer or downloader is implemented.
Builds without a configured public key do not start Sparkle; Check for Updates
explains the missing configuration instead of trusting an invented key.

These builds remain **ad-hoc signed and not notarized**. To load an embedded
framework without an Apple Team ID, the development app has the
`com.apple.security.cs.disable-library-validation` entitlement as documented by
Sparkle. This is a narrowly scoped development accommodation, not a Gatekeeper
bypass. Remove it when transitioning to properly Developer ID-signed distribution.
No Apple certificates or notarization secrets are required or fabricated.

## One-time key setup (on your Mac)

Do this **before the final manual installation**. A keyless build cannot later
learn a trusted public key from the internet.

1. Download the official [Sparkle 2.10.0 distribution](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0).
   Alternatively resolve this repository's macOS package with `swift package resolve`;
   the tools are under `.build/artifacts/sparkle/Sparkle/bin/` (locate `generate_keys`
   there if SwiftPM changes capitalization/layout).
2. In the distribution directory, generate one persistent identity in your Mac's
   login Keychain:

   ```sh
   ./bin/generate_keys --account Arkiv-development
   ```

   Save the printed **public** key (the base64 string for `SUPublicEDKey`). In
   GitHub → ish4ra/Arkiv → Settings → Secrets and variables → Actions → Variables,
   create repository variable **`SPARKLE_PUBLIC_ED_KEY`** with that exact string.
   CI embeds it in the built app's Info.plist; it is public and is not a secret.
3. Export the private key **outside any Git checkout**, using a private directory:

   ```sh
   mkdir -p "$HOME/.arkiv-signing"
   chmod 700 "$HOME/.arkiv-signing"
   umask 077
   ./bin/generate_keys --account Arkiv-development -x "$HOME/.arkiv-signing/arkiv.private-key"
   gh secret set SPARKLE_PRIVATE_ED_KEY --repo ish4ra/Arkiv < "$HOME/.arkiv-signing/arkiv.private-key"
   ```

   The required repository Actions secret is **`SPARKLE_PRIVATE_ED_KEY`**: the
   exact exported file contents, not its filename and not a second base64 encoding.
   You can also use GitHub's secret editor. Never paste it into issues, logs, Git,
   workflow YAML, or an app bundle. No PAT secret is needed: publishing uses the
   job-scoped `GITHUB_TOKEN` with `contents: write`.
4. Back up the export in an encrypted offline vault with a separate recovery copy.
   Keep the login Keychain copy. Remove the temporary export after verifying your
   backup. To restore on a replacement Mac, use `generate_keys --account
   Arkiv-development -f /secure/path/arkiv.private-key`. Do not regenerate/rotate
   the key casually: without Developer ID, losing this trust root may require
   another manual installation. Protect both the key and GitHub repository access.

The workflow skips publishing with a clear notice until **both** settings exist.
Ordinary build/test/DMG CI still runs. Never configure secrets on a fork for this
publisher; the public URLs intentionally identify ish4ra/Arkiv.

## Feed and build versions

The stable development feed URL embedded in Arkiv is:

```
https://github.com/ish4ra/Arkiv/releases/download/development-updates/appcast.xml
```

After both matrix jobs pass on main, CI signs the exact verified Universal ZIP,
verifies its signature against the embedded public key, signs the appcast, then
creates a **prerelease** `dev-<build>` with `Arkiv-universal.zip` and `appcast.xml`.
Only after publishing that immutable payload does it replace the feed asset in
the dedicated `development-updates` prerelease. No stable production release is
created. Feed updates are serialized and refuse a non-increasing remote version.
GitHub asset replacement can briefly return 404; Sparkle retries on a later check.
Do not delete releases that a feed references, reuse tags, or overwrite payloads.

`CFBundleVersion = 10000 + github.run_number * 100 + github.run_attempt` for this
existing macos.yml workflow. Keep this workflow's run-number sequence; do not
reset it, and use fewer than 100 attempts per run. Local builds default to 3, or
accept an explicit `ARKIV_BUILD_VERSION`. The human version stays 0.1.0; the update
UI includes the numeric development build. A SHA is never used as the machine
version. Dispatch a **new full workflow run** for every new test update; do not
rerun only the publish job using older artifacts.

All four existing DMG/ZIP artifacts remain available. Updates always use the
Universal ZIP so an arm64 installation can transition safely to the same feed as
Intel. macOS CI verifies the built app, mounted DMG and copied installation,
framework architectures/signatures/loadability, metadata, and real ZIP signing
with a disposable test identity. It rejects corrupted signatures/feeds and a
wrong embedded key. Disposable test keys are never committed or published.
The tracked-file guard rejects conventional private-key files/blocks; publishing
also rejects the exact configured secret in any tracked file. No heuristic can
identify every arbitrary random seed, so never export one into the repository.

## Real-Mac test

1. Configure the variable and secret, then Actions → **macOS foundation** →
   **Run workflow** on main. Confirm all jobs pass and the two development
   prereleases/feed are present. Download that run's arm64 or Universal DMG.
2. Quit Arkiv, replace `/Applications/Arkiv.app` once, eject the DMG and launch.
   This initial ad-hoc installation may still require the existing development
   Gatekeeper approval described in [release.md](release.md). Do not disable
   Gatekeeper globally. Confirm the menu does not report a missing key.
3. Dispatch another complete main workflow. Its larger build number produces a
   newer signed Universal update even if the source commit is unchanged.
4. In the installed app choose **Arkiv → Check for Updates…**. Confirm the newer
   build/version information, install, and relaunch. Verify the installed build
   number increased (About Arkiv or Info.plist), Finder Services still work, and
   ZIP browsing/extraction remain correct. No repeated manual DMG replacement or
   xattr command should be part of the normal signed update path.
5. Test declining the update, no-update status, background-check permission/toggle,
   offline recovery, and updating after finishing/cancelling extraction. Repeat
   on Intel with the Universal payload.

CI cannot prove the full interactive install/relaunch or local macOS security
policy. Those remain real-Mac acceptance tests, especially for ad-hoc builds.
EdDSA establishes update authenticity; it does not confer Apple notarization.

## Research references

Official documentation inspected for this integration:
[setup and signing](https://sparkle-project.org/documentation/),
[programmatic AppKit controller](https://sparkle-project.org/documentation/programmatic-setup/),
[security and automatic-check settings](https://sparkle-project.org/documentation/customization/),
[helper signing](https://sparkle-project.org/documentation/sandboxing/).
The official documentation repository and Sparkle 2.10.0 package/source were read
via GitHub, including `sign_update` stdin handling and signed-feed verification.
