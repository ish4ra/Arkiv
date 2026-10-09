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

#include <dirent.h>
#include <locale.h>
#ifdef __APPLE__
#include <xlocale.h>
#endif
#ifdef __linux__
#include <sys/syscall.h>
#endif

/* Both platforms provide an atomic no-replace rename. Never substitute rename(),
   which could overwrite a file created after the conflict preflight. */
static int move_exclusive(int from, const char *source, int to, const char *destination) {
#ifdef __APPLE__
    return renameatx_np(from, source, to, destination, RENAME_EXCL);
#elif defined(__linux__) && defined(SYS_renameat2)
    return (int)syscall(SYS_renameat2, from, source, to, destination, 1 /* RENAME_NOREPLACE */);
#else
    errno = ENOTSUP;
    return -1;
#endif
}
static int component(const char *name) {
    return safe_path(name) && !strchr(name, '/');
}
int arkiv_publish_extracted(const char *parent_path, const char *staging, const char *name,
                           int here, arkiv_cancel *token, size_t *published, char *error, size_t capacity) {
    *published = 0;
    if (!component(staging) || !component(name) || !strcmp(staging, name))
        return fail(error, capacity, "Invalid output folder name.");
    if (cancelled(token)) return 2;
    int parent = open(parent_path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (parent < 0) return fail(error, capacity, "Destination directory is unavailable or unsafe.");
    int source = openat(parent, staging, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (source < 0) { close(parent); return fail(error, capacity, "Extracted output is unavailable or unsafe."); }
    int result = 0;
    if (!here) {
        if (cancelled(token)) result = 2;
        else if (move_exclusive(parent, staging, parent, name) != 0) {
            result = errno == EEXIST ? 3 : 1;
            fail(error, capacity, "Cannot place the archive folder; check conflicts and permissions.");
        }
        close(source); close(parent); return result;
    }
    DIR *directory = fdopendir(source);
    if (!directory) { close(source); close(parent); return fail(error, capacity, "Cannot read extracted output."); }
    struct dirent *entry;
    /* A conflict known before publication leaves the destination completely untouched.
       Directories also conflict: never merge existing trees. Include hidden entries. */
    errno = 0;
    while ((entry = readdir(directory))) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        if (cancelled(token)) { result = 2; break; }
        struct stat existing;
        if (!component(entry->d_name) || fstatat(parent, entry->d_name, &existing, AT_SYMLINK_NOFOLLOW) == 0) {
            result = 3; fail(error, capacity, "An output name already exists; folders are not merged."); break;
        }
        if (errno != ENOENT) { result = fail(error, capacity, "Cannot check destination conflicts."); break; }
        errno = 0;
    }
    if (!result && errno) result = fail(error, capacity, "Cannot enumerate extracted output.");
    if (!result) {
        rewinddir(directory);
        errno = 0;
        while ((entry = readdir(directory))) {
            if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
            if (cancelled(token)) { result = 2; break; }
            if (move_exclusive(source, entry->d_name, parent, entry->d_name) != 0) {
                result = fail(error, capacity, "Placement stopped because of a conflict or filesystem error."); break;
            }
            (*published)++;
            errno = 0;
        }
        if (!result && errno) result = fail(error, capacity, "Cannot enumerate extracted output.");
    }
    closedir(directory);
    if (!result && unlinkat(parent, staging, AT_REMOVEDIR) != 0)
        result = fail(error, capacity, "Files were placed, but the empty staging folder could not be removed.");
    close(parent);
    return result;
}

#include <dirent.h>
#include <locale.h>
#ifdef __APPLE__
#include <xlocale.h>
#endif
/* Walk every ancestor without following links, including the final component. */
static int create_open(const char *path) {
    if (!path || path[0] != '/') { errno = EINVAL; return -1; }
    char *copy = strdup(path); if (!copy) return -1;
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    char *save = NULL;
    for (char *p = strtok_r(copy, "/", &save); p && fd >= 0; p = strtok_r(NULL, "/", &save)) {
        if (!strcmp(p, ".") || !strcmp(p, "..")) { close(fd); fd = -1; errno = EINVAL; break; }
        int next = openat(fd, p, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
        close(fd); fd = next;
    }
    free(copy); return fd;
}
struct create_state {
    struct archive *writer; arkiv_limits limits; arkiv_cancel *token;
    arkiv_progress_callback progress; void *context;
    uint64_t entries, bytes; char *error; size_t capacity;
    dev_t stage_dev; ino_t stage_ino;
};
static int create_walk(struct create_state *s, int fd, const char *path, unsigned depth) {
    if (cancelled(s->token)) return 2;
    struct stat st;
    if (depth > 128 || !safe_path(path) || fstat(fd, &st) ||
        (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode)) ||
        (st.st_dev == s->stage_dev && st.st_ino == s->stage_ino))
        return fail(s->error, s->capacity, "Source contains a link, special file, or unsafe path.");
    if (++s->entries > s->limits.max_entries || st.st_size < 0 ||
        (S_ISREG(st.st_mode) && (uint64_t)st.st_size > s->limits.max_bytes - s->bytes))
        return fail(s->error, s->capacity, "Creation safety limit exceeded.");
    struct archive_entry *entry = archive_entry_new();
    if (!entry) return fail(s->error, s->capacity, "Cannot allocate ZIP entry.");
    archive_entry_set_pathname_utf8(entry, path);
    archive_entry_set_filetype(entry, S_ISDIR(st.st_mode) ? AE_IFDIR : AE_IFREG);
    archive_entry_set_perm(entry, S_ISDIR(st.st_mode) ? 0755 : 0644);
    archive_entry_set_mtime(entry, st.st_mtime, 0);
    archive_entry_set_size(entry, S_ISDIR(st.st_mode) ? 0 : st.st_size);
    int result = archive_write_header(s->writer, entry); archive_entry_free(entry);
    if (result != ARCHIVE_OK) return fail(s->error, s->capacity, "Cannot write ZIP header.");
    if (S_ISDIR(st.st_mode)) {
        DIR *dir = fdopendir(dup(fd));
        if (!dir) return fail(s->error, s->capacity, "Cannot enumerate source folder.");
        struct dirent *item; int status = 0;
        for (;;) {
            errno = 0; item = readdir(dir);
            if (!item) { if (errno) status = fail(s->error, s->capacity, "Cannot read source folder."); break; }
            if (!strcmp(item->d_name, ".") || !strcmp(item->d_name, "..")) continue;
            char child[4097];
            if (snprintf(child, sizeof(child), "%s/%s", path, item->d_name) >= (int)sizeof(child)) {
                status = fail(s->error, s->capacity, "Source path is too long."); break;
            }
            int childfd = openat(fd, item->d_name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
            if (childfd < 0) { status = fail(s->error, s->capacity, "Cannot safely open source item."); break; }
            status = create_walk(s, childfd, child, depth + 1); close(childfd);
            if (status) break;
        }
        closedir(dir); if (status) return status;
    } else {
        char buffer[65536]; uint64_t count = 0;
        while (count < (uint64_t)st.st_size) {
            if (cancelled(s->token)) return 2;
            size_t wanted = (uint64_t)st.st_size - count < sizeof(buffer) ? (size_t)((uint64_t)st.st_size - count) : sizeof(buffer);
            ssize_t n = read(fd, buffer, wanted);
            if (n <= 0 || archive_write_data(s->writer, buffer, (size_t)n) != n)
                return fail(s->error, s->capacity, "Source changed or ZIP write failed.");
            count += (uint64_t)n; s->bytes += (uint64_t)n;
            if (s->progress) s->progress(s->context, s->entries, s->bytes);
        }
        struct stat after;
        if (fstat(fd, &after) || after.st_size != st.st_size || after.st_mtime != st.st_mtime || after.st_ctime != st.st_ctime)
            return fail(s->error, s->capacity, "Source changed during creation.");
    }
    struct stat final_stat;
    if (fstat(fd, &final_stat) || final_stat.st_size != st.st_size ||
        final_stat.st_mtime != st.st_mtime || final_stat.st_ctime != st.st_ctime)
        return fail(s->error, s->capacity, "Source changed during creation.");
    if (archive_write_finish_entry(s->writer) != ARCHIVE_OK) return fail(s->error, s->capacity, "Cannot finish ZIP entry.");
    if (s->progress) s->progress(s->context, s->entries, s->bytes);
    return 0;
}
int arkiv_create_zip(const char *const *sources, size_t count, const char *parent,
                     const char *stage, const char *name, int compression, arkiv_limits limits,
                     arkiv_cancel *token, arkiv_progress_callback progress, void *context,
                     char *error, size_t capacity) {
    if (cancelled(token)) return 2;
    if (!count || count > limits.max_entries || !safe_path(stage) || strchr(stage, '/') || !safe_path(name) || strchr(name, '/'))
        return fail(error, capacity, "Invalid creation request.");
    locale_t utf8 = newlocale(LC_CTYPE_MASK, "en_US.UTF-8", NULL);
    if (!utf8) utf8 = newlocale(LC_CTYPE_MASK, "C.UTF-8", NULL);
    if (!utf8) return fail(error, capacity, "UTF-8 filename support is unavailable.");
    locale_t previous = uselocale(utf8);
    int parentfd = create_open(parent), stagefd = -1, output = -1, status = 1;
    struct archive *writer = NULL, *verify = NULL;
    if (parentfd < 0) goto done;
    stagefd = openat(parentfd, stage, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (stagefd < 0) goto done;
    output = openat(stagefd, "archive.zip", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (output < 0) goto done;
    writer = archive_write_new();
    if (!writer || archive_write_set_format_zip(writer) != ARCHIVE_OK ||
        archive_write_set_format_option(writer, "zip", "compression", compression ? "deflate" : "store") != ARCHIVE_OK ||
        archive_write_set_format_option(writer, "zip", "hdrcharset", "UTF-8") != ARCHIVE_OK ||
        archive_write_open_fd(writer, output) != ARCHIVE_OK) goto done;
    struct stat stage_stat;
    if (fstat(stagefd, &stage_stat)) goto done;
    struct create_state state = { writer, limits, token, progress, context, 0, 0, error, capacity, stage_stat.st_dev, stage_stat.st_ino };
    for (size_t i = 0; i < count; i++) {
        int fd = create_open(sources[i]);
        if (fd < 0) goto done;
        const char *base = strrchr(sources[i], '/');
        status = create_walk(&state, fd, base ? base + 1 : sources[i], 0); close(fd);
        if (status) goto done;
    }
    status = 1;
    if (archive_write_close(writer) != ARCHIVE_OK || fsync(output) || lseek(output, 0, SEEK_SET) < 0) goto done;
    archive_write_free(writer); writer = NULL;
    verify = archive_read_new();
    if (!verify || archive_read_support_filter_none(verify) != ARCHIVE_OK ||
        archive_read_support_format_zip(verify) != ARCHIVE_OK || archive_read_open_fd(verify, output, 65536) != ARCHIVE_OK) goto done;
    struct archive_entry *entry; int r; uint64_t entries = 0, bytes = 0; char buffer[65536];
    while ((r = archive_read_next_header(verify, &entry)) == ARCHIVE_OK) {
        if (++entries > limits.max_entries || !entry_kind(entry)) goto done;
        ssize_t n;
        while ((n = archive_read_data(verify, buffer, sizeof(buffer))) > 0) {
            if (cancelled(token)) { status = 2; goto done; }
            if ((uint64_t)n > limits.max_bytes - bytes) goto done;
            bytes += (uint64_t)n;
        }
        if (n < 0) goto done;
    }
    if (r != ARCHIVE_EOF || entries != state.entries || bytes != state.bytes) goto done;
    if (cancelled(token)) { status = 2; goto done; }
    /* A same-filesystem hard link publishes atomically without replacing any item. */
    if (linkat(stagefd, "archive.zip", parentfd, name, 0)) { status = errno == EEXIST ? 3 : 1; goto done; }
    status = 0;
done:
    if (verify) archive_read_free(verify);
    if (writer) archive_write_free(writer);
    if (output >= 0) close(output);
    if (stagefd >= 0) { unlinkat(stagefd, "archive.zip", 0); close(stagefd); }
    if (parentfd >= 0) close(parentfd);
    uselocale(previous); freelocale(utf8);
    if (status == 1 && error && capacity && !error[0]) fail(error, capacity, "Cannot safely create or verify ZIP archive.");
    return status;
}
