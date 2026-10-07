#ifndef ARKO_ARCHIVE_H
#define ARKO_ARCHIVE_H
#include <stdint.h>
#include <stddef.h>

typedef struct arko_cancel arko_cancel;
arko_cancel *arko_cancel_new(void);
void arko_cancel_set(arko_cancel *token);
void arko_cancel_free(arko_cancel *token);

typedef struct {
    uint64_t max_entries;
    uint64_t max_bytes;
} arko_limits;
/* Callback strings are borrowed and valid only during the callback. */
typedef int (*arko_entry_callback)(void *, int64_t, const char *, int64_t, int);
typedef void (*arko_progress_callback)(void *, uint64_t, uint64_t);
/* Return 0 success, 1 error, 2 cancellation. Error buffer never contains archive data. */
int arko_list(const char *, arko_limits, arko_cancel *, arko_entry_callback, void *, char *, size_t);
/* Root must be a private, caller-owned directory. Never overwrites. IDs are sorted, unique archive ordinals;
   NULL IDs means all entries. Only regular files/directories; no links or special entries. */
int arko_extract(const char *, const char *, const int64_t *, size_t, arko_limits,
                 arko_cancel *, arko_progress_callback, void *, char *, size_t);
const char *arko_backend_version(void);
#endif
