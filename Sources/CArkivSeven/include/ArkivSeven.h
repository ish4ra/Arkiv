#ifndef ARKIV_SEVEN_H
#define ARKIV_SEVEN_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Only caller-owned descriptors are used. No archive path is ever opened by 7-Zip.
   0 success, 1 damaged/unsafe/unsupported, 2 cancelled, 4 password required, 5 wrong password.
   Password is borrowed for this synchronous call only. */
typedef int (*arkiv_seven_cancel)(void *);
typedef void (*arkiv_seven_progress)(void *, uint64_t, uint64_t);
__attribute__((visibility("default"))) const char *arkiv_seven_library_path(void);
__attribute__((visibility("default"))) int arkiv_seven_encode(int zipfd, int outputfd, const char *password, int headers, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
__attribute__((visibility("default"))) int arkiv_seven_decode(int inputfd, int zipfd, const char *password, arkiv_seven_cancel, void *);
__attribute__((visibility("default"))) int arkiv_seven_test(int, const char *, uint64_t, uint64_t, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
/* Append preserves all original packed streams; additions is a validated private ZIP. */
__attribute__((visibility("default"))) int arkiv_seven_probe_append(int inputfd);
__attribute__((visibility("default"))) int arkiv_seven_append(int originalfd, int additionsfd, int outputfd, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
__attribute__((visibility("default"))) int arkiv_seven_delete(int originalfd, const char *const *oldnames, const unsigned char *keep, uint64_t count, int outputfd, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
__attribute__((visibility("default"))) int arkiv_seven_rename(int originalfd, const char *const *oldnames, const char *const *newnames, uint64_t count, int outputfd, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
__attribute__((visibility("default"))) int arkiv_seven_replace(int, int, const char *const *, uint64_t, uint64_t, int, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
#ifdef __cplusplus
}
#endif
#endif
