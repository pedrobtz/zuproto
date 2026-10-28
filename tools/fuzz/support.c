/* The upb targets' pool, built once from tools/fuzz/data.h through the
 * shim, with no R, and its cache of arena ceilings, as a pool holds one. */
#include "fuzz.h"
#include "data.h"
#include "zpb_upb.h"

#include <stdlib.h>

const zpb_defpool *zpb_fuzz_pool(void);
zpb_ceilings *zpb_fuzz_ceilings(void);

const zpb_defpool *zpb_fuzz_pool(void)
{
    static zpb_defpool *pool = NULL;
    if (pool != NULL) return pool;
    pool = zpb_defpool_new();
    zpb_arena *a = zpb_arena_new();
    FUZZ_CHECK(pool != NULL && a != NULL);
    const zpb_fdset *set = zpb_fdset_parse((const char *) zpb_fuzz_descriptors,
                                           zpb_fuzz_descriptors_len, a);
    FUZZ_CHECK(set != NULL);
    char err[512];
    for (size_t i = 0; i < zpb_fdset_count(set); i++) {
        size_t len;
        char *buf = zpb_fdproto_serialize(zpb_fdset_file(set, i), a, &len);
        FUZZ_CHECK(buf != NULL);
        FUZZ_CHECK(zpb_defpool_add_file(pool, buf, len, a, err, sizeof err) != NULL);
    }
    zpb_arena_free(a);
    return pool;
}

/* The pool never changes after it is built, so the cache is never cleared. */
zpb_ceilings *zpb_fuzz_ceilings(void)
{
    static zpb_ceilings ceilings;
    return &ceilings;
}
