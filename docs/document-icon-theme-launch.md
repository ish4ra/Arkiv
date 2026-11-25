# Launching downloadable document icon themes

A one-time, step-by-step guide for the maintainer, on an Apple Silicon Mac.
It turns on the optional theme downloads that are already implemented in
Arkiv (see [document icon themes](document-icon-themes.md)). Everything here
is free: a public GitHub repository, GitHub Actions, GitHub Releases and tools
that come with macOS. No Apple Developer membership, paid hosting or database
is involved.

**What you will end up with**

* A dedicated Ed25519 **theme signing key**, made on your Mac and kept in an
  encrypted disk image. It is separate from the Sparkle update key, which this
  guide never touches.
* The protected GitHub environment `document-icon-themes`, holding the private
  key as a secret, usable only from `main` and only after you approve a run.
* The public key as a repository variable, so new app builds trust the catalogue.
* The first signed catalogue on the `document-icon-themes` branch, and the 20
  theme packs in the prerelease `document-icon-themes-v1`.

**Rules that apply throughout**

* Never paste the private key into a chat, an issue, a commit or a command
  line. The commands below read it from its file.
* Never generate or store the key inside a Git checkout. The tool refuses to.
* Do not reuse the Sparkle key. Every tool and the app build refuse it.

## Account requirements and limits

* The repository is **public**. That matters twice: environment **required
  reviewers** are free for public repositories (a private repository would
  need a paid GitHub plan), and the app reads the catalogue from
  `raw.githubusercontent.com` and the packs from Releases without signing in.
* You need **admin** access to the repository to create environments, secrets
  and variables. As the owner you have it.
* As the only reviewer you approve your own runs. Leave **Prevent self-review**
  off, or no one could approve them.
* GitHub may change the wording or placement of settings pages; the names
  below are those in use in November 2026.

## 1. Get the current scripts from `main`

Use a clean checkout of `main`, so that the key tool and the workflow are the
reviewed versions. A fresh clone is simplest:

```bash
git clone https://github.com/ish4ra/Arkiv.git ~/Developer/Arkiv-themes
```

```bash
cd ~/Developer/Arkiv-themes && git switch main && git pull --ff-only && git status --short && git log -1 --format='%H %s'
```

`git status --short` must print nothing. The commit should be the latest on
<https://github.com/ish4ra/Arkiv/commits/main>; at the time of writing, `d70c14c`
or a later merge. The tool is `scripts/document-icon-theme-catalog.swift`; it
has commands `production-key`, `verify-keypair`, `sign` and `verify`.

The publication workflow and theme inventory are already on `main`. You do not
need to wait for any other pull request to complete this guide.

## 2. Check the command-line tools

```bash
xcode-select -p
```

```bash
swift --version
```

```bash
gh --version
```

* `xcode-select -p` must print a path. If not, run `xcode-select --install`.
* `swift` must report Swift 5.9 or later (the tool uses CryptoKit, part of macOS).
* If `gh` is missing, install the free GitHub CLI with `brew install gh`, or the
  installer from <https://cli.github.com>. Then sign in:

```bash
gh auth login
```

```bash
gh auth status
```

Choose GitHub.com and HTTPS, and sign in as the repository owner.

## 3. Generate the production key outside the repository

Create a small encrypted disk image to hold the key, so that the private key is
never written unencrypted to your disk or to a Time Machine backup. macOS asks
you for a new password: make a strong one and save it in your password manager.

```bash
hdiutil create -size 32m -fs APFS -encryption AES-256 -volname ArkivThemeSigning ~/Documents/ArkivThemeSigning.dmg
```

```bash
hdiutil attach ~/Documents/ArkivThemeSigning.dmg
```

The volume appears at `/Volumes/ArkivThemeSigning`. Generate the key pair in
it, from the checkout of step 1:

```bash
cd ~/Developer/Arkiv-themes && swift scripts/document-icon-theme-catalog.swift production-key /Volumes/ArkivThemeSigning/keys
```

It prints a key ID, the two file paths and the **public** key value. It never
prints the private key, and it refuses to overwrite an existing key. Write down
the 16-character key ID; you will compare it later.

| File | Contents |
| --- | --- |
| `/Volumes/ArkivThemeSigning/keys/arkiv-theme-signing.key` | Private key (base64), mode 0600, in a 0700 folder. Secret |
| `/Volumes/ArkivThemeSigning/keys/arkiv-theme-signing.pub` | Public key (base64). Not secret |

## 4. Verify the key pair without showing the private key

```bash
stat -f '%Lp %N' /Volumes/ArkivThemeSigning/keys /Volumes/ArkivThemeSigning/keys/arkiv-theme-signing.key
```

It must print `700` for the folder and `600` for the key.

Check that the two files belong together and that neither is the Sparkle key.
This reads the Sparkle **public** key from the repository variable; it prints
key IDs only:

```bash
cd ~/Developer/Arkiv-themes && SPARKLE_PUBLIC_ED_KEY="$(gh variable get SPARKLE_PUBLIC_ED_KEY --repo ish4ra/Arkiv)" ARKIV_THEME_PRIVATE_ED_KEY="$(cat /Volumes/ArkivThemeSigning/keys/arkiv-theme-signing.key)" ARKIV_THEME_PUBLIC_ED_KEY="$(cat /Volumes/ArkivThemeSigning/keys/arkiv-theme-signing.pub)" swift scripts/document-icon-theme-catalog.swift verify-keypair
```

Expected: `Theme signing key pair matches (key <your key ID>)`.

## 5. Create the protected `document-icon-themes` environment

On GitHub: **ish4ra/Arkiv → Settings → Environments → New environment**.
Name it exactly `document-icon-themes` and choose **Configure environment**.

## 6. Require your approval and restrict it to `main`

On the same page:

1. **Required reviewers:** tick it, add yourself, and leave **Prevent
   self-review** unticked. Choose **Save protection rules**.
2. **Deployment branches and tags:** choose **Selected branches and tags** →
   **Add deployment branch or tag rule** → Ref type **Branch**, name pattern
   `main` → **Add rule**.
3. Leave **Wait timer** at 0. Leave **Allow administrators to bypass
   configured protection rules** unticked if your page shows it.

The workflow itself also refuses to publish unless it was started manually,
with **publish** ticked, on `main`.

## 7. Store the private key as an environment secret

The command reads the file through standard input, so the key never appears in
your shell history or on screen:

```bash
gh secret set ARKIV_THEME_PRIVATE_ED_KEY --repo ish4ra/Arkiv --env document-icon-themes < /Volumes/ArkivThemeSigning/keys/arkiv-theme-signing.key
```

```bash
gh secret list --repo ish4ra/Arkiv --env document-icon-themes
```

The list must show `ARKIV_THEME_PRIVATE_ED_KEY` (GitHub never shows its value).
Store it **only** in this environment, never as a repository-wide secret.

## 8. Store the public key as a repository variable

Set it at **repository** level, not only on the environment: the regular app
build reads it without entering the protected environment.

```bash
gh variable set ARKIV_THEME_PUBLIC_ED_KEY --repo ish4ra/Arkiv < /Volumes/ArkivThemeSigning/keys/arkiv-theme-signing.pub
```

```bash
gh variable get ARKIV_THEME_PUBLIC_ED_KEY --repo ish4ra/Arkiv
```

The printed value must equal `cat /Volumes/ArkivThemeSigning/keys/arkiv-theme-signing.pub`.

## 9. Back up the key safely

1. Eject the volume:

   ```bash
   hdiutil detach /Volumes/ArkivThemeSigning
   ```

2. Copy `~/Documents/ArkivThemeSigning.dmg` to a second place you control, such
   as an external drive. The image is encrypted, so copies are safe to keep.
3. Make sure its password is in your password manager. Without the password the
   copies are useless.
4. Optionally test the backup: attach the copy, run
   `cat /Volumes/ArkivThemeSigning/keys/arkiv-theme-signing.pub`, compare it with
   step 8, and detach again.

If the key is ever lost, existing installed themes keep working, but new
catalogues cannot be signed until you ship an app build that trusts a new key
([rotation](document-icon-themes.md#provisioning-maintainer)). If it is ever
exposed, delete the secret at once (`gh secret delete ARKIV_THEME_PRIVATE_ED_KEY
--repo ish4ra/Arkiv --env document-icon-themes`) and rotate.

## 10. Publish the first catalogue and packs

Start the workflow on `main` with publishing enabled, either from **Actions →
Document icon themes → Run workflow** (branch `main`, tick **publish**), or:

```bash
gh workflow run document-icon-themes.yml --repo ish4ra/Arkiv --ref main -f publish=true
```

1. The run first rebuilds all 20 packs from the preserved archives and requires
   them to be byte-identical to `inventory.json` (about 30–75 minutes), then
   installs every pack on Apple Silicon and Intel runners with a throwaway key.
2. The **Publish signed theme packs** job then waits for you. Open the run and
   check that the build jobs passed and that the uploaded
   `document-icon-theme-packs` artifact lists 20 themes. Choose **Review
   deployments**, tick `document-icon-themes`, and **Approve and deploy**.
3. The job checks the key pair, signs the catalogue, uploads the packs to a
   **draft** release, verifies every upload against GitHub's SHA-256 digests,
   publishes it as a **prerelease that is never marked Latest**, downloads every
   asset back from its public URL, and only then pushes `catalog.json` to the
   `document-icon-themes` branch.

**Verify the result:**

```bash
gh release view document-icon-themes-v1 --repo ish4ra/Arkiv --json isPrerelease,isDraft,assets --jq '{isPrerelease, isDraft, assets: (.assets | length)}'
```

Expected: `isPrerelease` true, `isDraft` false, 40 assets (20 packs and 20 preview packs).

```bash
curl -fsSL https://raw.githubusercontent.com/ish4ra/Arkiv/document-icon-themes/catalog.json -o /tmp/arkiv-catalog.json && cd ~/Developer/Arkiv-themes && ARKIV_THEME_PUBLIC_ED_KEY="$(gh variable get ARKIV_THEME_PUBLIC_ED_KEY --repo ish4ra/Arkiv)" swift scripts/document-icon-theme-catalog.swift verify /tmp/arkiv-catalog.json
```

Expected: `Catalogue signature valid (key <your key ID>)`.

Also open <https://github.com/ish4ra/Arkiv/releases>: the **Arkiv Development**
releases are unchanged, and `document-icon-themes-v1` is labelled Pre-release.

**If the publish job fails part-way**, choose **Re-run failed jobs** on the same
run. A rerun completes or repairs its own draft release and never overwrites a
published asset. One case looks like a failure but is not: if the log says the
catalogue was pushed but not yet served, wait a minute and repeat the `curl`
check above. A rerun after that point stops with "catalogue version is not newer
than the published one", because the catalogue is already live. To publish a
later catalogue, a reviewed change must raise its version first.

## 11. Build an app update that trusts the key

Builds read `ARKIV_THEME_PUBLIC_ED_KEY` when they are made, so build 30201 and
earlier do not trust any theme catalogue. Start a new `main` build (merging any
pull request into `main` does the same):

```bash
gh workflow run macos.yml --repo ish4ra/Arkiv --ref main
```

When it finishes, its **Publish signed development update** job releases a new
`dev-<build>` prerelease and updates the Sparkle feed. Sparkle signing is
unchanged by everything in this guide.

## 12. Verify the update and real theme downloads

On your Mac, with build 30201 or later installed in Applications:

1. **Arkiv → Check for Updates…** offers the new build. Install it. Sparkle
   verifies its EdDSA signature before installing.
2. Confirm the installed app trusts your key and is intact:

   ```bash
   /usr/libexec/PlistBuddy -c 'Print :ArkivDocumentIconThemePublicEDKey' /Applications/Arkiv.app/Contents/Info.plist
   ```

   ```bash
   codesign --verify --deep --strict /Applications/Arkiv.app && echo signature OK
   ```

   The first command must print the same value as step 8.
3. **Settings → Document Icons** (Settings → Appearance → Document Icon Theme
   in build 30701 and earlier) shows "Catalogue verified.
   20 themes available."
4. Download a small theme (Folio, about 4.5 MB): watch the progress, then
   **Apply**. Open an archive containing a nested archive: its row, the
   title-bar proxy icon and **Archive Info** use the new theme. Finder still
   shows Seal Dark.
5. Quit and relaunch: the theme is still applied. Turn Wi-Fi off and reopen the
   pane: it shows the offline notice, and the installed theme still works.
6. **Remove** the theme in use: Arkiv asks first, then returns to Seal Dark.
7. Run `codesign --verify --deep --strict /Applications/Arkiv.app` again: the
   app is unchanged by installing themes.

Then complete the remaining checks in
[real-Mac acceptance](document-icon-themes.md#remaining-real-mac-acceptance),
and update the wording marked below.

## After activation: wording to update

Once steps 10–12 have passed, update these statements in one reviewed pull request:

* **README → Document icons:** remove the "Theme downloads are not live yet"
  note, and add the first build number that trusts the key.
* **README → Roadmap:** move document icon themes from "Awaiting production
  activation" to "Published".
* [Document icon themes](document-icon-themes.md) status line, and
  [roadmap](roadmap.md) milestone 2: "published as catalogue v1; trusted from
  build _N_".
* [Feature matrix](feature-matrix.md): replace "first publication pending
  maintainer provisioning".
