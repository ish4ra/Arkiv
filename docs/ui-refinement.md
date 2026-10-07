# Native browser refinement

This milestone changes presentation and window routing only. The archive engine,
extraction policy, original icon, development signing, and arm64/Universal DMG
pipeline are unchanged.

- Open Archive (⌘O), the toolbar, and Finder opening share one routing policy.
  An idle empty window is reused, preferring the originating/key window. An
  archive already open or loading is brought forward. A different archive gets
  another window only when no idle empty window exists. Pending loads reserve
  their window immediately. New Window (⌘N) always creates an independent window.
  Automatic window tabbing is disabled.
- The initial view shows the original Arko icon, a short description, and Open
  Archive. There is no initial table. Drop-to-open is deferred; no drop hint is
  displayed.
- The native toolbar contains Open Archive, Extract Selected, Extract All, and
  Info. Unavailable actions are disabled. Navigation has Back, Forward, Up,
  current folder, and a compact archive-wide search field.
- The table uses a plain background, 26-point rows, reusable cells, native
  file/folder icons, a flexible Name column, right-aligned sizes, and native sort
  indicators. Sort/filter changes keep selection attached to paths; folder
  navigation clears selection. Right-clicking an unselected row selects it;
  right-clicking a selection preserves the selected group.
- The footer shows displayed rows, archive entry count, and selected count.
  Selected size appears only when all selected rows have known nonnegative sizes.
  Folder sizes are not invented. Search can include synthetic folder rows, so
  displayed row count and raw archive entry count are separate measures.

## Validation

`swift test` includes routing, reservation, sorting, selection, and size tests.
On macOS it also checks the actual empty-window controls, table configuration,
original-icon use, toolbar actions, and explicit multi-window behavior. Existing
engine tests continue unchanged. Both existing CI jobs build/sign/verify the app
and create/mount/verify the development DMGs.

Before treating visual polish as final, test the packaged app on a real Mac:

1. Launch without an archive; use ⌘O. Confirm the same window becomes the archive
   browser with no empty tab. Repeat with Finder opening and multiple files.
2. Open the same archive again while loading and after loading. Confirm it is
   focused. Use ⌘N and open a different archive from that empty window.
3. Resize down to the minimum and enlarge again. Check column widths, toolbar
   overflow, search, long paths, large sizes, and the empty area below a short list.
4. Check light/dark appearance, active/inactive multi-selection, VoiceOver labels,
   keyboard shortcuts, sorting, folder navigation, search clearing, and context
   menu extraction. Confirm the selected files remain the same after sorting.
5. Extract selected files and all files; cancel a long operation. Confirm the
   existing progress, destination sheet, cleanup, and Finder reveal still work.

The Linux development environment cannot assess native macOS rendering or
VoiceOver output. Passing CI establishes build/test/package validity, not a
substitute for these interactive visual checks.
