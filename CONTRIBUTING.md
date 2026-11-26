# Contributing to Arkiv

Thank you for helping. Arkiv is a native macOS archive manager written in
Swift and AppKit; see the [README](README.md), [architecture](docs/architecture.md)
and [roadmap](docs/roadmap.md).

## Licence of contributions

Arkiv is licensed under the [GNU GPL-3.0-or-later](LICENSE). By submitting a
pull request, issue attachment or theme artwork you agree that it is licensed
under GPL-3.0-or-later (the same terms as the project, "inbound = outbound"),
and you confirm that you wrote it or otherwise have the right to submit it
under those terms, as in the [Developer Certificate of Origin](https://developercertificate.org/).
A `Signed-off-by:` line (`git commit -s`) is welcome but not required.

You keep the copyright in your contribution. There is no contributor licence
agreement and no copyright assignment.

* Do not copy code, artwork or fixtures from projects whose licence is not
  GPL-3.0-compatible, or whose licence you do not know.
* If you add third-party material, keep its original licence and notices,
  add it to [third-party notices](docs/third-party-licenses.md) (and `NOTICE`
  for anything shipped in the app), and say so in the pull request. Code
  under the 7-Zip unRAR restriction (`Compress/Rar*`) is not accepted.
* New Swift, C and script files may start with
  `// SPDX-License-Identifier: GPL-3.0-or-later` (or `#` for scripts).
  Files without a header are covered by the root `LICENSE` and `NOTICE`.
  Files in `Vendor/7zip` and `Sources/CArkivSeven` stay LGPL-2.1-or-later.
* The name and icon are covered by the [name and logo policy](TRADEMARKS.md).

## Before opening a pull request

* Build and test on macOS 13 or later: `swift build` and `swift test`, or
  `scripts/ci-check.sh` for the full packaging checks.
* Keep the safety rules in [security](docs/security.md): no overwriting, no
  background services, no telemetry, no network access outside updates and
  the theme pane.
* New archive formats or volume schemes must keep the document-icon coverage
  rule across all theme families ([roadmap](docs/roadmap.md)).
* Never attach private archives or passwords to issues or pull requests; use
  synthetic test data.

Security problems: please do not post exploit details in a public issue. Use
GitHub's private vulnerability reporting (Security → Report a vulnerability)
if it is enabled for the repository; otherwise open an issue asking for a
private contact, without details.
