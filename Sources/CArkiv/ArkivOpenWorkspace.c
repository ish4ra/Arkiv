#include "ArkivArchive.h"
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

/* Only this app's private, versioned root is eligible for sweeping. All traversal
   and deletion is relative to pinned descriptors; symlinks are never followed. */
struct arkiv_open_workspace { int root, session; char *path; char name[45]; };
static int owned_directory(int fd) {
    struct stat s;
    return fstat(fd, &s) == 0 && S_ISDIR(s.st_mode) && s.st_uid == geteuid() && (s.st_mode & 0777) == 0700;
}
static int walk(int fd, const char *path) {
    char *copy = strdup(path); if (!copy) { close(fd); return -1; }
    char *save = NULL;
    for (char *p = strtok_r(copy, "/", &save); p && fd >= 0; p = strtok_r(NULL, "/", &save)) {
        if (!strcmp(p, ".") || !strcmp(p, "..")) { close(fd); fd = -1; break; }
        int next = openat(fd, p, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
        close(fd); fd = next;
    }
    free(copy); return fd;
}
static int same(int parent, const char *name, int fd) {
    struct stat a, b;
    return fstatat(parent, name, &a, AT_SYMLINK_NOFOLLOW) == 0 && fstat(fd, &b) == 0 && a.st_dev == b.st_dev && a.st_ino == b.st_ino;
}
static int uuid_name(const char *name, const char *prefix) {
    size_t n = strlen(prefix);
    if (strncmp(name, prefix, n) || strlen(name + n) != 36) return 0;
    for (int i = 0; i < 36; i++) {
        char c = name[n + i];
        if (i == 8 || i == 13 || i == 18 || i == 23) { if (c != '-') return 0; }
        else if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f'))) return 0;
    }
    return 1;
}
static int clear_directory(int fd, dev_t device, unsigned depth) {
    if (depth > 512) return -1;
    DIR *dir = fdopendir(openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    if (!dir) return -1;
    int result = 0; struct dirent *entry;
    while ((entry = readdir(dir))) {
        const char *name = entry->d_name;
        if (!strcmp(name, ".") || !strcmp(name, "..")) continue;
        struct stat s;
        if (fstatat(fd, name, &s, AT_SYMLINK_NOFOLLOW) || s.st_dev != device || s.st_uid != geteuid()) { result = -1; continue; }
        if (S_ISDIR(s.st_mode)) {
            int child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (child < 0) { result = -1; continue; }
            if (same(fd, name, child) && !clear_directory(child, device, depth + 1) && same(fd, name, child)) {
                if (unlinkat(fd, name, AT_REMOVEDIR)) result = -1;
            } else result = -1;
            close(child);
        } else if (unlinkat(fd, name, 0)) result = -1;
    }
    closedir(dir); return result;
}
static void remove_directory(int parent, const char *name, int fd) {
    struct stat s;
    if (fstat(fd, &s) == 0 && same(parent, name, fd) && !clear_directory(fd, s.st_dev, 0) && same(parent, name, fd))
        (void)unlinkat(parent, name, AT_REMOVEDIR);
}
static void sweep(int root) {
    DIR *dir = fdopendir(openat(root, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC));
    if (!dir) return;
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (!uuid_name(entry->d_name, "session-")) continue;
        int fd = openat(root, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (fd < 0) continue;
        /* A live process keeps its directory locked, including while idle. */
        if (owned_directory(fd) && flock(fd, LOCK_EX | LOCK_NB) == 0)
            remove_directory(root, entry->d_name, fd);
        close(fd);
    }
    closedir(dir);
}
static int open_root(const char *parent, char *name, size_t size) {
    if (!parent || parent[0] != '/') return -1;
    int fd = walk(open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC), parent);
    if (fd < 0) return -1;
    snprintf(name, size, "xyz.isharalakshan.arkiv.open-v1-%lu", (unsigned long)geteuid());
    if (mkdirat(fd, name, 0700) && errno != EEXIST) { close(fd); return -1; }
    int root = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (root >= 0 && (!owned_directory(root) || !same(fd, name, root))) { close(root); root = -1; }
    close(fd); return root;
}
void arkiv_open_sweep(const char *parent) {
    char name[80]; int root = open_root(parent, name, sizeof(name));
    if (root < 0) return;
    if (flock(root, LOCK_EX) == 0) sweep(root);
    close(root);
}
arkiv_open_workspace *arkiv_open_workspace_new(const char *parent, const char *name) {
    if (!uuid_name(name, "session-")) return NULL;
    char root_name[80]; int root = open_root(parent, root_name, sizeof(root_name));
    if (root < 0) return NULL;
    if (flock(root, LOCK_EX)) { close(root); return NULL; }
    sweep(root);
    int fd = -1;
    if (!mkdirat(root, name, 0700)) fd = openat(root, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0 || !owned_directory(fd) || flock(fd, LOCK_EX | LOCK_NB)) {
        if (fd >= 0) close(fd);
        close(root); return NULL;
    }
    arkiv_open_workspace *workspace = calloc(1, sizeof(*workspace));
    size_t length = strlen(parent) + strlen(root_name) + strlen(name) + 3;
    if (workspace) workspace->path = malloc(length);
    if (!workspace || !workspace->path) { free(workspace); remove_directory(root, name, fd); close(fd); close(root); return NULL; }
    snprintf(workspace->path, length, "%s/%s/%s", parent, root_name, name);
    workspace->root = root; workspace->session = fd;
    snprintf(workspace->name, sizeof(workspace->name), "%s", name);
    flock(root, LOCK_UN); return workspace;
}
const char *arkiv_open_workspace_path(arkiv_open_workspace *w) { return w->path; }
int arkiv_open_workspace_attempt(arkiv_open_workspace *w, const char *name) {
    return uuid_name(name, "file-") && !mkdirat(w->session, name, 0700) ? 0 : 1;
}
void arkiv_open_workspace_discard(arkiv_open_workspace *w, const char *name) {
    if (!uuid_name(name, "file-")) return;
    int fd = openat(w->session, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd >= 0) { if (owned_directory(fd)) remove_directory(w->session, name, fd); close(fd); }
}
int arkiv_open_workspace_regular(arkiv_open_workspace *w, const char *relative) {
    if (!relative || !*relative || *relative == '/') return 0;
    int fd = walk(dup(w->session), relative);
    if (fd < 0) return 0;
    struct stat s;
    int valid = fstat(fd, &s) == 0 && S_ISREG(s.st_mode) && s.st_nlink == 1 && s.st_uid == geteuid();
    close(fd); return valid;
}
void arkiv_open_workspace_free(arkiv_open_workspace *w) {
    if (!w) return;
    if (flock(w->root, LOCK_EX) == 0) {
        remove_directory(w->root, w->name, w->session);
        flock(w->root, LOCK_UN);
    }
    close(w->session); close(w->root); free(w->path); free(w);
}
