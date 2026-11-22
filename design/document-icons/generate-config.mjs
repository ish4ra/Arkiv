// Production icon table. Resource name → artwork id (lib/formats.mjs) and the
// file extensions Finder shows it for. Keep in sync with Resources/Info.plist
// and scripts/verify-document-icons.py (ICONS).
export const ICONS = {
  ZIP: { format: 'zip', ext: '.zip' },
  '7z': { format: '7z', ext: '.7z' },
  TAR: { format: 'tar', ext: '.tar' },
  RAR: { format: 'rar', ext: '.rar' },
  GZIP: { format: 'gz', ext: '.gz · .tar.gz' },
  BZIP2: { format: 'bz2', ext: '.bz2 · .tar.bz2' },
  XZ: { format: 'xz', ext: '.xz · .tar.xz' },
  ZSTD: { format: 'zst', ext: '.zst · .tar.zst · .tzst' },
  TGZ: { format: 'tgz', label: 'TGZ', ext: '.tgz' },
};
