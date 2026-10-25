/* JSON text as any of zpb_fuzz_types (the first byte picks), parsed by
 * upb's JSON decoder, then encoded as binary and as JSON again. */
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

    size_t len = size - 1;
    char *text = (char *) malloc(len ? len : 1);
    if (text == NULL) return 0;
    if (len) memcpy(text, data + 1, len);

    zpb_counting_alloc ca;
    zpb_arena *a = zpb_arena_new_limited(&ca, 4 * len + 65536);
    zpb_msg *msg = a ? zpb_msg_new(m, a) : NULL;
    char err[512];
    if (msg != NULL && zpb_json_decode(text, len, msg, m, pool, (data[0] & 0x80) != 0, a, err, sizeof err)) {
        int status;
        size_t n = 0;
        zpb_encode_message(msg, m, true, false, a, &n, &status);
        size_t j = zpb_json_encode(msg, m, pool, ZPB_JSON_EMIT_DEFAULTS, NULL, 0, err, sizeof err);
        if (j != (size_t) -1) {
            char *json = (char *) malloc(j + 1);
            if (json != NULL) {
                FUZZ_CHECK(zpb_json_encode(msg, m, pool, ZPB_JSON_EMIT_DEFAULTS, json, j + 1, err,
                                           sizeof err) == j);
                free(json);
            }
        }
    }
    if (a != NULL) zpb_arena_free(a);
    free(text);
    return 0;
}
