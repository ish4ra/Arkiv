# Open Recent

File → Open Recent uses NSDocumentController's recent-document persistence and
Clear Menu API, presented as a standard NSMenu. Arkiv retains its existing window
architecture; no NSDocument conversion or alternate archive reader is involved.
Only successful normal opens register. Nested leases and Arkiv-owned temporary
paths/spools are excluded. Selecting a recent URL uses the same canonical opener
as Finder, Services and Open Archive; missing files receive the normal error UI.
Missing/unreadable entries remain available for retry until Clear Menu (there is
no public single-URL removal API used here). No passwords are stored.

Real-Mac validation: open several real archives, check newest-first ordering,
quit/relaunch and check persistence, then open a recent item. Confirm an already
open archive reuses its window. Move/delete an archive and verify a normal error
without substitution. Clear Menu and relaunch. Open a nested archive and verify
its temporary URL never enters recents. Settings remains unimplemented.
