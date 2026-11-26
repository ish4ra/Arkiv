# Public beta readiness

Assessment for distributing Arkiv to communities such as FMHY, Reddit and
Discord. Nothing here publishes a build. State as of pull request
[#8](https://github.com/ish4ra/Arkiv/pull/8) (Ledger redesign, not yet merged;
published build 30701).

## Readiness

### Safe and ready now

* **Archive engine and safety model**: read-only browsing and extraction,
  private staging, no overwrite, path and link checks, budgets, transactional
  verified edits ([security](security.md)); large automated suites on macOS
  CI for Apple Silicon and Intel.
* **Signed in-app updates**: Sparkle EdDSA-signed development channel with
  monotonic build numbers ([updates](updates.md)).
* **Document icon themes**: Ed25519-signed catalogue, verified packs, offline
  use, removal and fallback; 20 themes published.
* **Network and privacy behaviour**: no accounts, telemetry or background
  services; network only for update checks/downloads and the theme pane
  (README → Safety and privacy).
* **Downloads without a GitHub account** from the Releases page, with
  GitHub-published SHA-256 digests for every asset.

### Must be fixed before a public beta

1. **Redesign real-Mac acceptance**: complete
   [real-Mac acceptance](real-mac-acceptance.md) on the maintainer's Mac,
   merge #8 and publish it through the normal signed channel.
2. **Update path from 30701**: confirm Check for Updates from 30701 installs
   the redesign build and keeps preferences and themes (acceptance §1).
3. **Project licence: done.** Arkiv is GPL-3.0-or-later, with a separate
   [name and logo policy](../TRADEMARKS.md) ([licensing](licensing-assessment.md)).
   What remains is per release: every release must link its exact source
   commit and keep the 7-Zip library replaceable
   ([release obligations](release.md#licence-obligations-for-every-release)).
4. **Clear first-install instructions on the release page itself**: today the
   release body is one line. Each beta release needs install, Gatekeeper,
   verification and known-limitation notes (template below), because many
   users arrive from a link straight to the release.
5. **A bug-reporting path that works without guessing**: issue templates
   (below), and a note that reporting needs a free GitHub account; offer an
   alternative contact if the maintainer wants reports without one.
6. **Known limitations stated up front**: ad-hoc signing, no notarization,
   RAR read-only, editing limited to eligible ZIP/7z, no Finder theme
   switching, development-quality status.

### Recommended, not mandatory

* RAR multipart reading and split ZIP (milestones 5–6), since they are the
  most likely early requests.
* A permanent "latest build" URL (proposal in [download links](release.md#download-links)).
* `SECURITY.md` at the repository root with a private reporting route
  (GitHub private vulnerability reporting is free).
* Real-Mac launch time, memory and idle CPU figures in the README.
* Developer ID signing and notarization (paid Apple Developer Program): the
  single biggest improvement to first-run trust, but not required for a beta
  that explains the Gatekeeper step.

### Post-launch roadmap

The rest of the [roadmap](roadmap.md): Quick Look thumbnail evaluation, more
RAR features, encrypted ZIP editing, editing more formats, archive comments,
checksums, split/combine, benchmark, command-line companion, delta updates,
hostile-input fuzzing and an isolated decoder helper.

## Can a new user…

| Question | Today | Gap |
| --- | --- | --- |
| Find the right download without a GitHub account? | Yes: README button to the verified build, plus an application-only release list | Release pages need install notes |
| Identify supported macOS versions and architectures? | README: macOS 13 or later; Universal (Apple Silicon and Intel) | Repeat on the release page |
| Understand installation and Gatekeeper? | README explains Open Anyway; never suggests disabling Gatekeeper | Repeat on the release page |
| Verify download integrity? | GitHub shows a SHA-256 digest per asset; DMG artefacts carry `.sha256` | README now explains it; release notes should repeat the digest |
| Update through Sparkle? | Yes, EdDSA-verified, with confirmation | — |
| Report bugs easily? | Issues link in README (GitHub account required) | Templates; optional non-GitHub contact |
| Understand formats and limits? | README format table, feature matrix | Short "known limitations" in release notes |
| Understand network activity and privacy? | README Safety and privacy | Optional `PRIVACY.md` mirror |

## Beta release strategy

Keep **one** update channel and **one** build-number sequence:

* A public beta is an ordinary development build (`dev-<build>`, monotonic
  `CFBundleVersion`, same Sparkle feed), chosen after acceptance and
  **renamed** on GitHub as *Arkiv Public Beta 1 (build N)*, with the full
  release-notes template. Testers on earlier builds receive it through
  Sparkle exactly as today; later development builds keep updating beta
  users, so no second feed or key is introduced.
* Optionally raise `CFBundleShortVersionString` from `0.1.0` to a beta
  marketing version (for example `0.9.0`) at that build. Sparkle compares the
  build number, so the display version can change freely.
* The README button points to the named beta release; the application-only
  release list remains for "newest".
* Do not mark it as GitHub "Latest" while builds are prereleases; the
  application-only search link avoids depending on that.

## Templates to add (recommended)

**Issue templates** (`.github/ISSUE_TEMPLATE/`):

1. *Bug report*: Arkiv build (About Arkiv), macOS version, Mac model
   (Apple Silicon/Intel), how installed (release ZIP, DMG, Sparkle update),
   archive format and size (no private archives), steps, expected/actual,
   screenshots; a reminder never to attach passwords or private data.
2. *Archive compatibility*: format, creating tool and settings, whether other
   tools open it, a public or synthetic sample if possible.
3. *Feature request*: problem first, then proposal.
4. `config.yml`: link security reports to private reporting, and questions to
   Discussions if enabled.

**Release notes template** (per beta):

* What's new; known limitations; requirements (macOS 13+, Universal).
* Install: download `Arkiv-universal.zip`, check its SHA-256 (shown on the
  release page; `shasum -a 256 Arkiv-universal.zip`), move to Applications,
  first-open Gatekeeper step (Open Anyway), never disable Gatekeeper globally.
* Signing statement: ad-hoc signed, **not notarized**; updates are
  EdDSA-signed by this project (not Apple notarization).
* Privacy: no telemetry; network only for updates and the theme pane.
* Licence and source: GPL-3.0-or-later (7-Zip library LGPL-2.1-or-later);
  link to the exact commit and its source archive.
* How to report problems.

**Tester guide** (`docs/testing-the-beta.md`, to write at beta time): a short
public version of the acceptance checklist using disposable archives.

**Privacy and security documents**: keep [security](security.md) as the
technical reference; add a root `SECURITY.md` (supported builds, private
reporting route, response expectations) and a short `PRIVACY.md` (exactly
which network requests happen, when, to which hosts, and that nothing
personal is sent), linked from the README and release notes.

## Feature priorities

1. Ledger redesign acceptance and release (pull request #8).
2. RAR multipart reading (milestone 5).
3. Split ZIP support (milestone 6).
4. Public beta hardening: the must-fix items above, templates, privacy and
   security documents (licence done).
5. Community launch.

Every new archive format or volume scheme keeps the permanent
document-icon-coverage rule across all compatible theme families
([roadmap](roadmap.md)). Neither RAR multipart nor split ZIP is part of the
redesign pull request.
