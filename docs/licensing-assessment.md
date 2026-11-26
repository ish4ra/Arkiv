# Licensing

**Decision: Arkiv is licensed under the GNU General Public License, version 3
or (at your option) any later version (`GPL-3.0-or-later`).** The official,
unmodified licence text is the root [`LICENSE`](../LICENSE); scope and
separately licensed parts are in [`NOTICE`](../NOTICE); the name and icon are
covered by the [name and logo policy](../TRADEMARKS.md); contributions follow
[`CONTRIBUTING.md`](../CONTRIBUTING.md). The app ships `LICENSE.txt` and
`NOTICE.txt` in `Contents/Resources`, next to `ThirdPartyNotices.txt`.

This page records why, what each component requires, and what is still open.
It is an engineering assessment, not legal advice.

## Why GPL-3.0-or-later

The maintainer's goals, and how each candidate meets them:

| Goal | MIT | Apache-2.0 | MPL-2.0 | GPL-3.0-or-later |
| --- | --- | --- | --- | --- |
| Free, OSI-approved open source | Yes | Yes | Yes | Yes |
| Inspect, modify, build, redistribute | Yes | Yes | Yes | Yes |
| Commercial use (selling, using at work, bundling) | Yes | Yes | Yes | Yes |
| Redistributed derivatives stay open | No: closed forks allowed | No | Only modified MPL files | **Yes: whole program, with source** |
| Explicit patent licence | No | Yes | Yes | Yes |
| Compatible with 7-Zip LGPL, BSD, MIT, 0BSD, zlib | Yes | Yes | Yes | Yes |
| Accepted by free-software lists (FMHY, Reddit, Discord) | Yes | Yes | Yes | Yes |

Only the GPL meets the goal of **protecting against redistributed
closed-source derivatives**: anyone may sell or bundle Arkiv, but whoever
distributes a modified Arkiv must give recipients its complete source under
the same licence. MIT and Apache-2.0 would let a closed fork take the work;
MPL-2.0 protects only files that are modified, not a fork that adds closed
code around them. Arkiv is an end-user application, not a library other
programs embed, so the GPL's main cost for libraries (preventing closed
programs from linking it) does not apply. "Or later" keeps Arkiv able to move
to future GPL versions without asking every contributor; it is also how the
7-Zip library is licensed.

What it means in practice:

* **Commercial use:** allowed without asking, including selling builds.
* **Redistribution:** unmodified or modified, with the licence and notices
  and an offer of the complete corresponding source.
* **Proprietary forks:** not allowed. A distributed fork is GPL, with source.
  Private modifications that are never distributed have no obligations.
* **Source disclosure:** whole program, to anyone who receives a binary.
* **Mac App Store:** its terms are generally considered incompatible with
  GPL redistribution by third parties; the maintainer, as copyright holder of
  Arkiv's own code, could still publish there, but the 7-Zip LGPL library and
  any third-party GPL contributions would need care. Not a current plan.

## Artwork and branding

* **Copyright:** the app icon, Tension Seal renderer, bundled and downloadable
  document icons, theme packs and README artwork are original project work
  and are covered by GPL-3.0-or-later like the code. One licence for
  everything in the app keeps distribution simple and avoids non-free parts
  inside a free app. Forks may reuse the artwork.
* **Name and logo:** protected separately, as GPL-3.0 section 7(e) allows, by
  the [name and logo policy](../TRADEMARKS.md): unmodified builds may be
  redistributed under the name Arkiv; modified versions use a different name,
  icon, bundle identifier and update feed. It restricts no GPL right in the
  code or artwork.
* **Fonts:** the Inter Display files are the font authors' work under OFL 1.1
  and are not relicensed; rendered labels are not font software.

## Third-party obligations


| Component | How it is used | Licence | Obligations when distributing Arkiv |
| --- | --- | --- | --- |
| **7-Zip** 26.04 source subset (`Vendor/7zip`, commit `9128b80`) | Built into a separate dynamic library, `Contents/Frameworks/libArkivSeven.dylib` | GNU **LGPL-2.1-or-later**; some files BSD-2/BSD-3 or public domain as marked | Keep `License.txt`/`copying.txt` (already packaged in the app); provide the corresponding source of the library and its build scripts (the tagged repository commit); allow users to replace the library with a modified one (the app loads it dynamically; [replacement steps](sevenzip.md#build-and-replacement)); do not forbid reverse engineering for debugging such modifications |
| 7-Zip **RAR** code (unRAR restriction) | **Not included.** `Compress/Rar*` files are not vendored ([sources list](../Vendor/7zip/sources.txt)); RAR is read through the system libarchive | LGPL + unRAR restriction | None today. Adding them later would add the unRAR restriction (no use to recreate the RAR compression algorithm), which is not an OSI-approved condition |
| **Arkiv's own code** (Swift app, ArkivCore, ArkivThemes, scripts, CI) | Main executable, extensions, tooling | **GPL-3.0-or-later** | Source for the exact build; keep `LICENSE`/`NOTICE` (packaged) |
| Arkiv 7-Zip bridge (`Sources/CArkivSeven`, `scripts/build-sevenzip.py`) | Part of the dylib | LGPL-2.1-or-later (already granted) | Same as 7-Zip |
| **libarchive** | macOS **system** library (`/usr/lib/libarchive`); Arkiv vendors only its API headers (BSD) | BSD-2-Clause | Keep notices (packaged); Apple ships the system library |
| **zlib, bzip2, liblzma** | macOS system libraries; Arkiv vendors bzip2 and XZ headers | zlib, bzip2 (BSD-style), XZ 0BSD | Keep the bundled header notices (packaged) |
| **Zstandard** 1.5.7 | Statically compiled into Arkiv | BSD-3-Clause (chosen option of BSD/GPLv2 dual licence) | Keep the notice (packaged) |
| **Sparkle** 2.10.0 | Embedded framework | MIT (with its own bundled third-party notices) | Keep its licence (packaged as `Sparkle-LICENSE.txt`) |
| **Inter Display** fonts (`design/document-icons/fonts`) | Design-time only, to render icon lettering into PNG artwork; not in the app | SIL Open Font License 1.1 | None for the shipped app (rendered images are not font software). Redistributing the font files in the repository requires keeping `OFL.txt` and not selling the fonts alone |
| App icon, document icons, theme packs, README artwork | Original project artwork | GPL-3.0-or-later, like the code; name and Tension Seal mark under the [name and logo policy](../TRADEMARKS.md) | Same as the code |
| Test fixtures | Test-only, never in the app | BSD corpus notices (libarchive, WinZip AES fixtures) in `licenses/`; others are original | Keep the notices with the repository |
| Test-only Python packages (pyzipper MIT, PyCryptodome BSD/public domain) | Downloaded in CI, hash-pinned | Permissive | None for the app |
| Design tooling (Playwright, Node packages in `design/`) | Not distributed with the app | Their own permissive licences | None for the app |

**Confirmed compatible.** LGPL-2.1-or-later, BSD-2/BSD-3, MIT, 0BSD and
zlib licences are all compatible with GPL-3.0-or-later. Apple's system
frameworks and libraries (AppKit, libarchive, zlib, libbz2, liblzma) are
system libraries under GPL-3.0 section 1, so they need not be distributed as
source. No component is relicensed: the 7-Zip library and bridge remain
LGPL-2.1-or-later and replaceable; third-party notices are packaged unchanged.

**Release obligations** (see [release](release.md#licence-obligations-for-every-release)):
complete corresponding source for each build (tagged commit plus GitHub's
source archives), packaged licences and notices, a replaceable
`libArkivSeven.dylib`, and no added restrictions.

## Unresolved questions

None blocks the licence; they are recorded so nothing is overstated.

1. **Published theme packs** (catalogue already signed and live) carry the
   earlier statement "Arkiv has not yet selected a project licence; no other
   licence is granted" (`design/document-icon-themes/themes.json`). This
   change does not touch production theme assets. As copyright holder the
   project now licenses that artwork under GPL-3.0-or-later through the
   repository `LICENSE`; the maintainer should update the `licence` string
   at the next deliberate theme publication.
2. **Trademark enforceability:** "Arkiv" and Tension Seal are unregistered
   marks, and the name is a common word in several languages. The policy
   states intent and relies on GPL-3.0 section 7(e); how far it can be
   enforced is a legal question this assessment does not answer.
3. **Contributor provenance:** all commits so far are by the maintainer or by
   development sessions working for the maintainer, so the maintainer can
   license them. Future contributions are inbound = outbound under
   GPL-3.0-or-later (`CONTRIBUTING.md`).
4. **Developer ID and notarization:** library validation in a future
   notarized build must not prevent LGPL library replacement (see release
   obligations).
5. **Adding 7-Zip RAR code** would add the unRAR restriction, which is not
   GPL-compatible; it stays excluded.
