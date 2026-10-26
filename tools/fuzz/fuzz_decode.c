/* One message as any of zpb_fuzz_types (the first byte picks), decoded by
 * upb into an arena on zuproto's counting allocator, then written as JSON
 * (behind zpb_check_any(), as zpb_to_json() does) and re-encoded.
 * Invariants: a message that decodes re-encodes, and its
 * deterministic encoding decodes back to bytes that encode the same. */
#include "fuzz.h"
#include "zpb_upb.h"

#include <stdlib.h>

const zpb_defpool *zpb_fuzz_pool(void);
int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    FUZZ_CANARY(data, size);
    if (size < 1 || size > (1 << 20)) return 0;
    const zpb_defpool *pool = zpb_fuzz_pool();
    const zpb_msgdef *m = zpb_defpool_find_message(pool, zpb_fuzz_types[data[0] % ZPB_FUZZ_NTYPES]);
    FUZZ_CHECK(m != NULL);

    /* An exact-size copy, so ASan sees any overread. */
    size_t len = size - 1;
    char *buf = (char *) malloc(len ? len : 1);
    if (buf == NULL) return 0;
    if (len) memcpy(buf, data + 1, len);

    zpb_counting_alloc ca;
    zpb_arena *a = zpb_arena_new_limited(&ca, (size_t) zpb_arena_ceiling(pool, m, (double) len, 1));
    int status;
    const zpb_msg *msg = a ? zpb_decode_message(pool, m, buf, len, a, 100, &status) : NULL;
    if (msg != NULL) {
        char err[512];
        /* zuproto bounds every Any before upb's JSON encoder sees it (design
         * section 12), so JSON is written only for a message that passes. */
        size_t n = zpb_check_any(pool, m, msg, 100, a, &ca) == ZPB_DECODE_OK
                       ? zpb_json_encode(msg, m, pool, 0, NULL, 0, err, sizeof err)
                       : (size_t) -1;
        if (n != (size_t) -1) {
            char *json = (char *) malloc(n + 1);
            if (json != NULL) {
                FUZZ_CHECK(zpb_json_encode(msg, m, pool, 0, json, n + 1, err, sizeof err) == n);
                free(json);
            }
        }
        size_t b1_len = 0, b2_len = 0;
        char *b1 = zpb_encode_message(msg, m, true, false, a, &b1_len, &status);
        if (b1 != NULL) {
            const zpb_msg *again = zpb_decode_message(pool, m, b1, b1_len, a, 100, &status);
            /* The memory cap can refuse the second decode; nothing else may. */
            FUZZ_CHECK(again != NULL || ca.exceeded);
            if (again != NULL) {
                char *b2 = zpb_encode_message(again, m, true, false, a, &b2_len, &status);
                FUZZ_CHECK(b2 != NULL || ca.exceeded);
                if (b2 != NULL) FUZZ_CHECK(b1_len == b2_len && memcmp(b1, b2, b1_len) == 0);
            }
        }
    }
    if (a != NULL) zpb_arena_free(a);
    free(buf);
    return 0;
}
