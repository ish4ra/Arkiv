# Archive document icons

ZIP, 7z, TAR and RAR use a shared warm paper silhouette, folded corner, plum
format label and the unchanged Tension Seal mark. There are no new app-icon
backgrounds, recolored marks or external artwork. The original app renderer and
all six branding exports are pinned by `branding/app-icon-preservation.json`.

`scripts/render-document-icons.swift` deterministically draws each iconset with
AppKit and the authoritative transparent branding PNG. The build uses Apple's
iconutil to bundle `Arkiv-ZIP.icns`, `Arkiv-7z.icns`, `Arkiv-TAR.icns`, and
`Arkiv-RAR.icns` in Contents/Resources. Representations cover 16, 32, 64, 128,
256, 512 and 1024 physical pixels, including standard Retina iconset pairs.
Typography uses the runner's native macOS system font; pixel-identical rendering
across different macOS font versions is not promised. Both architectures use the
same source, geometry, colors and representation checks.

Existing ZIP/TAR UTIs retain Viewer/Alternate registration. 7z and RAR add
Viewer/Alternate document declarations and imported (not exported/owned) UTIs:
`org.7-zip.7-zip-archive` and `com.rarlab.rar-archive`. No default handler is
changed programmatically. RAR remains read-only with limited verified decoding;
the icon is not a promise of RAR creation or universal RAR compatibility.

Every packaged-app verification, including mounted DMGs and extracted update
payloads, checks document declarations, ICNS decoding, all representation sizes,
transparent corners and opaque document centers. Source tests pin original
branding and reject missing icon references or default-ownership claims.

## Real-Mac visual acceptance (not automated)

1. Install the packaged app; confirm its original application icon is unchanged.
2. Using Get Info → Open with, associate representative ZIP/7z/TAR/RAR files with
   Arkiv only if desired. Existing defaults remain yours to choose.
3. Inspect Finder icon, list, column and gallery views, small through large sizes,
   on Retina and non-Retina displays where available.
4. Check labels, silhouette, padding and edges against light and dark backgrounds.
5. Confirm ordinary open behavior and format limitations are unchanged.

Finder controls icon selection, thumbnails and caching. Existing custom icons or
Quick Look thumbnails can take precedence; automatic resource tests cannot prove
Finder visual appearance. Do not reset Launch Services or caches to install these
icons. Real-Mac visual validation remains required.
