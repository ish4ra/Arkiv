#include "ArkivArchive.h"
#include "vendor/archive.h"
#include "vendor/archive_entry.h"
#include <errno.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

struct arkiv_cancel { atomic_int value; };
arkiv_cancel *arkiv_cancel_new(void) {
    arkiv_cancel *p = malloc(sizeof(*p));
    if (p) atomic_init(&p->value, 0);
    return p;
}
void arkiv_cancel_set(arkiv_cancel *p) { if (p) atomic_store(&p->value, 1); }
void arkiv_cancel_free(arkiv_cancel *p) { free(p); }
static int cancelled(arkiv_cancel *p) { return p && atomic_load(&p->value); }
const char *arkiv_backend_version(void) { return archive_version_string(); }
static int fail(char *error, size_t capacity, const char *message) {
    if (error && capacity) snprintf(error, capacity, "%s", message);
    return 1;
}

/* Deliberately register only in-process filters and the initial candidate formats.
   Never enable libarchive's external-program filter fallback. */
static struct archive *reader(const char *path) {
    struct archive *a = archive_read_new();
    if (!a) return NULL;
    archive_read_support_filter_none(a);
    archive_read_support_format_zip(a);
    archive_read_support_format_tar(a);
    archive_read_support_format_7zip(a);
    archive_read_support_format_rar(a);
    archive_read_support_format_rar5(a);
    if (archive_read_open_filename(a, path, 65536) != ARCHIVE_OK) {
        archive_read_free(a); return NULL;
    }
    return a;
}

/* Strict relative paths. Backslashes/colons also reject foreign absolute/device paths.
   No ambiguous normalization: reject dot components and empty interior components. */
static int safe_path(const char *path) {
    if (!path || !*path || *path == '/' || strlen(path) > 4096) return 0;
    const char *part = path;
    for (const char *p = path;; p++) {
        if (*p == '\\' || *p == ':' || ((unsigned char)*p < 32 && *p)) return 0;
        if (*p == '/' || !*p) {
            size_t n = (size_t)(p - part);
            if (!n || (n == 1 && part[0] == '.') ||
                (n == 2 && part[0] == '.' && part[1] == '.')) return 0;
            if (!*p || !p[1]) return 1;
            part = p + 1;
        }
    }
}
static int entry_kind(struct archive_entry *e) {
    if (archive_entry_symlink(e) || archive_entry_hardlink(e)) return 0;
    if (archive_entry_filetype(e) == AE_IFREG) return 1;
    if (archive_entry_filetype(e) == AE_IFDIR) return 2;
    return 0;
}
int arkiv_list(const char *path, arkiv_limits limits, arkiv_cancel *token,
              arkiv_entry_callback callback, void *context, char *error, size_t capacity) {
    if (cancelled(token)) return 2;
    struct archive *a = reader(path);
    if (!a) return fail(error, capacity, "Cannot read archive: unsupported, encrypted, corrupt, or inaccessible.");
    struct archive_entry *e;
    int status, result = 0;
    uint64_t count = 0;
    while ((status = archive_read_next_header(a, &e)) == ARCHIVE_OK) {
        if (cancelled(token)) { result = 2; break; }
        if (count >= limits.max_entries) { result = fail(error, capacity, "Archive entry limit exceeded."); break; }
        const char *name = archive_entry_pathname_utf8(e);
        if (!name || !safe_path(name)) { result = fail(error, capacity, "Unsafe or invalid archive path."); break; }
        if (callback && callback(context, (int64_t)count, name, archive_entry_size(e), entry_kind(e))) {
            result = fail(error, capacity, "Archive listing was rejected."); break;
        }
        count++;
        if (archive_read_data_skip(a) != ARCHIVE_OK) { result = fail(error, capacity, "Cannot skip damaged archive entry."); break; }
    }
    if (!result && cancelled(token)) result = 2;
    if (!result && status != ARCHIVE_EOF) result = fail(error, capacity, "Archive header is damaged or unsupported.");
    archive_read_free(a);
    return result;
}

/* Walk from an already-open root, refusing symlinks at EVERY component.
   The caller owns a private root; archive metadata can never create a link. */
static int open_output(int root, const char *name, int directory) {
    char *copy = strdup(name);
    if (!copy) return -1;
    size_t length = strlen(copy);
    if (length && copy[length - 1] == '/') copy[length - 1] = 0;
    int parent = dup(root), result = -1;
    if (parent < 0) { free(copy); return -1; }
    char *part = copy;
    for (;;) {
        char *slash = strchr(part, '/');
        if (slash) *slash = 0;
        if (slash || directory) {
            if (mkdirat(parent, part, 0700) != 0 && errno != EEXIST) break;
            int next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (next < 0) break;
            close(parent); parent = next;
            if (!slash) { result = parent; parent = -1; break; }
            part = slash + 1;
        } else {
            result = openat(parent, part, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
            break;
        }
    }
    if (parent >= 0) close(parent);
    free(copy);
    return result;
}
static int selected(int64_t id, const int64_t *ids, size_t count) {
    if (!ids) return 1;
    size_t low = 0, high = count;
    while (low < high) {
        size_t mid = low + (high - low) / 2;
        if (ids[mid] == id) return 1;
        if (ids[mid] < id) low = mid + 1; else high = mid;
    }
    return 0;
}
int arkiv_extract(const char *path, const char *root_path, const int64_t *ids, size_t selected_count,
                 arkiv_limits limits, arkiv_cancel *token, arkiv_progress_callback progress,
                 void *context, char *error, size_t capacity) {
    if (cancelled(token)) return 2;
    for (size_t i = 0; i < selected_count; i++) {
        if (ids[i] < 0) return fail(error, capacity, "Invalid selection.");
        if (i && ids[i] <= ids[i - 1]) return fail(error, capacity, "Selection must be sorted and unique.");
    }
    int root = open(root_path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (root < 0) return fail(error, capacity, "Output directory is unavailable or unsafe.");
    struct archive *a = reader(path);
    if (!a) { close(root); return fail(error, capacity, "Cannot read archive: unsupported, encrypted, corrupt, or inaccessible."); }
    struct archive_entry *e;
    int status, result = 0;
    uint64_t count = 0, total = 0, files = 0, found = 0;
    char buffer[65536];
    while ((status = archive_read_next_header(a, &e)) == ARCHIVE_OK) {
        if (cancelled(token)) { result = 2; break; }
        if (count >= limits.max_entries) { result = fail(error, capacity, "Archive entry limit exceeded."); break; }
        int wanted = selected((int64_t)count++, ids, selected_count);
        if (!wanted) {
            if (archive_read_data_skip(a) != ARCHIVE_OK) { result = fail(error, capacity, "Damaged archive data."); break; }
            continue;
        }
        found++;
        const char *name = archive_entry_pathname_utf8(e);
        int kind = entry_kind(e);
        if (!safe_path(name) || !kind) { result = fail(error, capacity, "Unsafe archive path, link, or special file."); break; }
        if (archive_entry_is_encrypted(e) > 0) { result = fail(error, capacity, "Encrypted extraction is not available yet."); break; }
        int64_t size = archive_entry_size(e);
        if (size < 0 || (uint64_t)size > limits.max_bytes - total) { result = fail(error, capacity, "Expanded size limit exceeded."); break; }
        int output = open_output(root, name, kind == 2);
        if (output < 0) { result = fail(error, capacity, "Output conflict, unsafe directory, or permission denied."); break; }
        if (kind == 1) {
            for (;;) {
                if (cancelled(token)) { result = 2; break; }
                la_ssize_t n = archive_read_data(a, buffer, sizeof(buffer));
                if (n < 0) { result = fail(error, capacity, "Archive data is corrupt, encrypted, or unsupported (including CRC failure)."); break; }
                if (!n) break;
                if ((uint64_t)n > limits.max_bytes - total) { result = fail(error, capacity, "Expanded size limit exceeded."); break; }
                size_t offset = 0;
                while (offset < (size_t)n) {
                    ssize_t written = write(output, buffer + offset, (size_t)n - offset);
                    if (written < 0 && errno == EINTR) continue;
                    if (written <= 0) { result = fail(error, capacity, "Cannot write output; check disk space and permissions."); break; }
                    offset += (size_t)written;
                }
                if (result) break;
                total += (uint64_t)n;
                if (progress) progress(context, files, total);
            }
        }
        if (close(output) != 0 && !result) result = fail(error, capacity, "Cannot finish writing output.");
        if (result) break;
        files++;
        if (progress) progress(context, files, total);
    }
    if (!result && cancelled(token)) result = 2;
    if (!result && status != ARCHIVE_EOF) result = fail(error, capacity, "Archive is truncated, damaged, or unsupported.");
    if (!result && ids && found != selected_count) result = fail(error, capacity, "Selected entries no longer exist in the archive.");
    archive_read_free(a);
    close(root);
    return result;
}
