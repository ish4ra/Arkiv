# Project licence assessment

**Status: no project-wide licence has been chosen.** The repository is public,
but that does not make Arkiv open source: without a licence, copyright law
reserves all rights, so others may view the code but have no granted right to
use, modify or redistribute Arkiv's own code. Third-party components keep their
own licences (below). Choosing a licence is the maintainer's decision; this
page only prepares it. It is not legal advice.

## What Arkiv ships and links

| Component | How it is used | Licence | Obligations when distributing Arkiv |
| --- | --- | --- | --- |
| **7-Zip** 26.04 source subset (`Vendor/7zip`, commit `9128b80`) | Built into a separate dynamic library, `Contents/Frameworks/libArkivSeven.dylib` | GNU **LGPL-2.1-or-later**; some files BSD-2/BSD-3 or public domain as marked | Keep `License.txt`/`copying.txt` (already packaged in the app); provide the corresponding source of the library and its build scripts (the tagged repository commit); allow users to replace the library with a modified one (the app loads it dynamically; [replacement steps](sevenzip.md#build-and-replacement)); do not forbid reverse engineering for debugging such modifications |
| 7-Zip **RAR** code (unRAR restriction) | **Not included.** `Compress/Rar*` files are not vendored ([sources list](../Vendor/7zip/sources.txt)); RAR is read through the system libarchive | LGPL + unRAR restriction | None today. Adding them later would add the unRAR restriction (no use to recreate the RAR compression algorithm), which is not an OSI-approved condition |
| Arkiv 7-Zip bridge (`Sources/CArkivSeven`, `scripts/build-sevenzip.py`) | Part of the dylib | LGPL-2.1-or-later (already granted) | Same as 7-Zip |
| **libarchive** | macOS **system** library (`/usr/lib/libarchive`); Arkiv vendors only its API headers (BSD) | BSD-2-Clause | Keep notices (packaged); Apple ships the system library |
| **zlib, bzip2, liblzma** | macOS system libraries; Arkiv vendors bzip2 and XZ headers | zlib, bzip2 (BSD-style), XZ 0BSD | Keep the bundled header notices (packaged) |
| **Zstandard** 1.5.7 | Statically compiled into Arkiv | BSD-3-Clause (chosen option of BSD/GPLv2 dual licence) | Keep the notice (packaged) |
| **Sparkle** 2.10.0 | Embedded framework | MIT (with its own bundled third-party notices) | Keep its licence (packaged as `Sparkle-LICENSE.txt`) |
| **Inter Display** fonts (`design/document-icons/fonts`) | Design-time only, to render icon lettering into PNG artwork; not in the app | SIL Open Font License 1.1 | None for the shipped app (rendered images are not font software). Redistributing the font files in the repository requires keeping `OFL.txt` and not selling the fonts alone |
| App icon, document icons, theme packs, README artwork | Original project artwork | Not yet licensed (all rights reserved by default) | Decide separately from the code (see below) |
| Test fixtures | Test-only, never in the app | BSD corpus notices (libarchive, WinZip AES fixtures) in `licenses/`; others are original | Keep the notices with the repository |
| Test-only Python packages (pyzipper MIT, PyCryptodome BSD/public domain) | Downloaded in CI, hash-pinned | Permissive | None for the app |
| Design tooling (Playwright, Node packages in `design/`) | Not distributed with the app | Their own permissive licences | None for the app |

**Compatibility conclusion.** Every component Arkiv distributes is permissive
except the 7-Zip library, which is LGPL and isolated as a replaceable dynamic
library. That arrangement is compatible with **any** project licence, permissive
or copyleft, including a proprietary one, provided the LGPL obligations for that
library are met. Nothing in the current tree forces Arkiv's own code to be GPL.

One practical caution: LGPL replacement must remain possible. Today builds are
ad-hoc signed with library validation disabled (`Development.entitlements`), so
a user can swap the library and re-sign locally. A future Developer ID,
notarized build with library validation should keep documenting how a user can
re-sign after replacing the library, or keep library validation disabled for it.

## Options for Arkiv's own code

| | MIT | Apache-2.0 | MPL-2.0 | GPL-3.0-or-later |
| --- | --- | --- | --- | --- |
| Commercial use | Yes | Yes | Yes | Yes |
| Redistribution | Yes, keep notice | Yes, keep notice and NOTICE file | Yes | Yes, with complete source under GPL |
| Modification | Yes | Yes, mark changed files | Yes; changed MPL files stay MPL | Yes; modified versions must be GPL |
| Proprietary forks | Allowed | Allowed | Allowed (new files may be closed; modified MPL files must stay open) | Not allowed: distributed forks must be GPL with source |
| Source disclosure | None | None | Only for modified MPL-licensed files | Whole program, when distributed |
| Patent grant | Implicit at most | Explicit, with termination on patent suit | Explicit | Explicit |
| Compatibility with current components | Yes | Yes | Yes | Yes (LGPL-2.1+, BSD, MIT, 0BSD, zlib are GPL-3-compatible) |
| Effect on Sparkle (MIT) and 7-Zip (LGPL) | None | None | None | None |

**Recommendation for the maintainer to consider:**

* If the goal is the widest adoption and the least friction for contributors
  and redistributors (community sites such as FMHY favour clearly open
  projects), **Apache-2.0** for the code is a good default: permissive like MIT,
  plus an explicit patent licence and a clear contribution rule. **MIT** is the
  simpler alternative if a minimal licence is preferred.
* If the goal is that any redistributed or forked Arkiv must stay open source,
  **GPL-3.0-or-later** achieves that and remains compatible with every
  component above. It prevents closed-source forks and some app-store
  distribution models.
* **MPL-2.0** is the middle ground (file-level copyleft).
* Whatever is chosen for the code, consider licensing the **name, app icon and
  Tension Seal branding** separately (for example "all rights reserved; forks
  must use a different name and icon"), and decide whether the document-icon
  artwork and theme packs follow the code licence or a Creative Commons
  licence (for example CC BY 4.0). Keeping the brand separate protects users
  from look-alike forks without restricting the code.

## Before declaring Arkiv open source

1. Maintainer chooses the licence(s) (code; artwork; brand).
2. Add `LICENSE` (and `NOTICE` for Apache-2.0) at the repository root; state
   the artwork and brand terms in `branding/README.md`.
3. Confirm every contributor's commits may be released under it (all code so
   far is by the maintainer and development sessions working for the
   maintainer; preserve that provenance).
4. Package the project licence in the app next to `ThirdPartyNotices.txt`.
5. Release notes for each build link the exact source commit (LGPL
   corresponding source for the 7-Zip library).
6. Only then describe Arkiv as free and open-source software.
