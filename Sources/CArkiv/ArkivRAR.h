#ifndef ARKIV_RAR_H
#define ARKIV_RAR_H
#include "ArkivArchive.h"
/* Header evidence only; payload decoding remains exclusively in libarchive. */
typedef struct { int64_t packed, crc, mode, attributes; unsigned method, version, directory; } arkiv_rar_item;
/* 0 valid/non-RAR, 2 cancelled, 6 corrupt, 8 unsupported, 10 multipart.
   missing_checksum means a complete decode must report Warning, not CRC success. */
int arkiv_rar_scan(int fd, arkiv_limits, arkiv_cancel *, int *version, int *missing_checksum,
                   arkiv_rar_item **items, size_t *count);
#endif
