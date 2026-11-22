// Format registry, verified against the repository on 2026-11-22:
//   Sources/ArkivCore/ArchiveCreator.swift  (creation suffixes and aliases)
//   Resources/Info.plist                    (document types and UTIs)
//   docs/archive-formats.md, docs/compressed-tar.md, docs/zstandard.md, docs/multipart.md
//
// status: 'supported' = Arkiv reads it today; 'future' = concept only, NOT supported.

export const BRAND = {
  plumHi: '#703A47', plumLo: '#301A2B', plumInk: '#4A2232',
  amberHi: '#FDCF73', amberLo: '#C46E38',
  jadeHi: '#CFF0D4', jadeLo: '#4A9C82',
  paperHi: '#FFFDFA', paperLo: '#F1EBE3',
};

// Hue families. light / base / dark / ink (label text on paper).
export const HUE = {
  zip:  { light: '#FFDC8C', base: '#EBA43C', dark: '#A65E1B', ink: '#7C4512', name: 'Amber' },
  '7z': { light: '#A9E6CF', base: '#3FA287', dark: '#1B6352', ink: '#165445', name: 'Jade' },
  rar:  { light: '#EBA2BB', base: '#A8476D', dark: '#5C1D3A', ink: '#5A1C38', name: 'Claret' },
  tar:  { light: '#B4CAEA', base: '#5779AB', dark: '#2B456F', ink: '#263E63', name: 'Slate' },
  gz:   { light: '#FFB49C', base: '#E06440', dark: '#983120', ink: '#882C1C', name: 'Coral' },
  bz2:  { light: '#D6DF92', base: '#8C9C3F', dark: '#4C581B', ink: '#434E18', name: 'Moss' },
  xz:   { light: '#C2B5F7', base: '#7863CB', dark: '#3D2C87', ink: '#38297B', name: 'Iris' },
  zst:  { light: '#A2DBF4', base: '#2F95C8', dark: '#135C87', ink: '#104D72', name: 'Cerulean' },
};

// kind: 'base' | 'tar' (compressed TAR) | 'split' (volume of a set)
export const FORMATS = [
  { id: 'zip', label: 'ZIP', short: 'ZIP', kind: 'base', hue: 'zip', motif: 'zip', ext: ['.zip'], uti: 'public.zip-archive', status: 'supported' },
  { id: '7z', label: '7Z', short: '7Z', kind: 'base', hue: '7z', motif: '7z', ext: ['.7z'], uti: 'org.7-zip.7-zip-archive', status: 'supported' },
  { id: 'rar', label: 'RAR', short: 'RAR', kind: 'base', hue: 'rar', motif: 'rar', ext: ['.rar'], uti: 'com.rarlab.rar-archive', status: 'supported', note: 'read-only' },
  { id: 'tar', label: 'TAR', short: 'TAR', kind: 'base', hue: 'tar', motif: 'tar', ext: ['.tar'], uti: 'public.tar-archive', status: 'supported' },
  { id: 'gz', label: 'GZIP', short: 'GZ', kind: 'base', hue: 'gz', motif: 'gz', ext: ['.gz'], uti: 'org.gnu.gnu-zip-archive', status: 'supported' },
  { id: 'bz2', label: 'BZIP2', short: 'BZ2', kind: 'base', hue: 'bz2', motif: 'bz2', ext: ['.bz2'], uti: 'public.bzip2-archive', status: 'supported' },
  { id: 'xz', label: 'XZ', short: 'XZ', kind: 'base', hue: 'xz', motif: 'xz', ext: ['.xz'], uti: 'org.tukaani.xz-archive', status: 'supported' },
  { id: 'zst', label: 'ZSTD', short: 'ZST', kind: 'base', hue: 'zst', motif: 'zst', ext: ['.zst'], uti: 'org.zstandard.zstd', status: 'supported' },
  { id: 'tgz', label: 'TAR.GZ', alias: 'TGZ', short: 'TGZ', kind: 'tar', hue: 'gz', motif: 'gz', ext: ['.tar.gz', '.tgz'], status: 'supported' },
  { id: 'tbz2', label: 'TAR.BZ2', alias: 'TBZ2', short: 'TBZ', kind: 'tar', hue: 'bz2', motif: 'bz2', ext: ['.tar.bz2', '.tbz2'], status: 'supported' },
  { id: 'txz', label: 'TAR.XZ', alias: 'TXZ', short: 'TXZ', kind: 'tar', hue: 'xz', motif: 'xz', ext: ['.tar.xz', '.txz'], status: 'supported' },
  { id: 'tzst', label: 'TAR.ZST', alias: 'TZST', short: 'TZS', kind: 'tar', hue: 'zst', motif: 'zst', ext: ['.tar.zst', '.tzst'], status: 'supported' },
  { id: '7z-split', label: '7Z', short: '7Z', kind: 'split', hue: '7z', motif: '7z', ext: ['.7z.001', '.7z.002', '…'], status: 'supported', note: '2–128 parts, read + create' },
  { id: 'rar-parts', label: 'RAR', short: 'RAR', kind: 'split', hue: 'rar', motif: 'rar', ext: ['.part1.rar', '.part2.rar', '.r00'], status: 'future' },
  { id: 'zip-split', label: 'ZIP', short: 'ZIP', kind: 'split', hue: 'zip', motif: 'zip', ext: ['.z01', '.zip.001'], status: 'future' },
];

export const byId = Object.fromEntries(FORMATS.map((x) => [x.id, x]));
