/* A stand-in for libFuzzer where the compiler has none (Apple clang): runs
 * each file named on the command line through the target, then mutates
 * them (bit flips, byte changes, truncations, splices) for the number of
 * seconds in ZPB_FUZZ_SECONDS. Coverage-blind, so CI's libFuzzer run is the
 * real campaign; this checks that targets build, run their seeds, and
 * crash on the canary. */
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);
/* A default for targets without one; a target's own definition wins. */
__attribute__((weak)) int LLVMFuzzerInitialize(int *argc, char ***argv)
{
    (void) argc;
    (void) argv;
    return 0;
}

typedef struct {
    uint8_t *p;
    size_t n;
} buf;

/* The input being run, written to crash-input when a run dies, so it can be
 * replayed: `<target> crash-input`. */
static const uint8_t *current;
static size_t current_n;

static void save_crash(int sig)
{
    FILE *f = fopen("crash-input", "wb");
    if (f) {
        fwrite(current, 1, current_n, f);
        fclose(f);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static int run(const uint8_t *p, size_t n)
{
    current = p;
    current_n = n;
    return LLVMFuzzerTestOneInput(p, n);
}

static buf read_file(const char *path)
{
    buf b = {NULL, 0};
    FILE *f = fopen(path, "rb");
    if (!f) return b;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    b.p = (uint8_t *) malloc(n > 0 ? (size_t) n : 1);
    if (b.p && n > 0 && fread(b.p, 1, (size_t) n, f) == (size_t) n) b.n = (size_t) n;
    fclose(f);
    return b;
}

int main(int argc, char **argv)
{
    LLVMFuzzerInitialize(&argc, &argv);
    signal(SIGILL, save_crash);
    signal(SIGABRT, save_crash);
    signal(SIGSEGV, save_crash);
    signal(SIGTRAP, save_crash);
    int nseeds = argc - 1;
    buf *seeds = (buf *) calloc(nseeds > 0 ? (size_t) nseeds : 1, sizeof *seeds);
    for (int i = 0; i < nseeds; i++) {
        seeds[i] = read_file(argv[i + 1]);
        run(seeds[i].p, seeds[i].n);
    }
    const char *s = getenv("ZPB_FUZZ_SECONDS");
    double secs = s ? atof(s) : 0;
    if (nseeds == 0 || secs <= 0) return 0;
    srand((unsigned) time(NULL));
    time_t end = time(NULL) + (time_t) secs;
    unsigned long runs = 0;
    uint8_t *m = (uint8_t *) malloc(1 << 16);
    while (time(NULL) < end) {
        buf b = seeds[rand() % nseeds];
        size_t n = b.n < (1 << 15) ? b.n : (1 << 15);
        memcpy(m, b.p, n);
        int edits = 1 + rand() % 8;
        for (int e = 0; e < edits; e++) {
            switch (rand() % 5) {
            case 0: if (n) m[rand() % n] ^= (uint8_t) (1u << (rand() % 8)); break;
            case 1: if (n) m[rand() % n] = (uint8_t) rand(); break;
            case 2: if (n) n = (size_t) rand() % n; break;
            case 3: if (n + 8 < (1 << 16)) for (int k = 0; k < 8; k++) m[n++] = (uint8_t) rand(); break;
            case 4: {
                buf o = seeds[rand() % nseeds];
                size_t k = o.n < 64 ? o.n : 64;
                if (n + k < (1 << 16)) { memcpy(m + n, o.p, k); n += k; }
                break;
            }
            }
        }
        if (n == 0) m[n++] = 0;
        run(m, n);
        runs++;
    }
    fprintf(stderr, "standalone: %lu runs in %.0f s, no crash\n", runs, secs);
    return 0;
}
