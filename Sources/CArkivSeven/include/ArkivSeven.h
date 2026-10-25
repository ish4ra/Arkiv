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
__attribute__((visibility("default"))) uint64_t arkiv_seven_creation_memory(unsigned, uint32_t, unsigned, uint64_t);
__attribute__((visibility("default"))) int arkiv_seven_encode_advanced(int, int, const char *, int, arkiv_seven_cancel, void *, arkiv_seven_progress, void *, unsigned, unsigned, unsigned);
__attribute__((visibility("default"))) int arkiv_seven_encode_level(int, int, const char *, int, arkiv_seven_cancel, void *, arkiv_seven_progress, void *, unsigned);
__attribute__((visibility("default"))) int arkiv_seven_encode(int zipfd, int outputfd, const char *password, int headers, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
__attribute__((visibility("default"))) int arkiv_seven_decode(int inputfd, int zipfd, const char *password, arkiv_seven_cancel, void *);
__attribute__((visibility("default"))) int arkiv_seven_test(int, const char *, uint64_t, uint64_t, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
/* Policy bits: 1 data encryption, 2 header encryption, 4 mixed encrypted/plain
   data, 8 supported future layout, 16 all data verified with supplied password.
   No write authorization. Failure outputs are diagnostic only. */
__attribute__((visibility("default"))) int arkiv_seven_policy(int, const char *, uint32_t *, arkiv_seven_cancel, void *);
__attribute__((visibility("default"))) int arkiv_seven_replace_encrypted(int, int, const char *const *, uint64_t, uint64_t, int, const char *, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
__attribute__((visibility("default"))) int arkiv_seven_append_encrypted(int, int, int, const char *, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
__attribute__((visibility("default"))) int arkiv_seven_delete_encrypted(int, const char *const *, const unsigned char *, uint64_t, int, const char *, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
__attribute__((visibility("default"))) int arkiv_seven_rename_encrypted(int, const char *const *, const char *const *, uint64_t, int, const char *, arkiv_seven_cancel, void *, arkiv_seven_progress, void *);
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
