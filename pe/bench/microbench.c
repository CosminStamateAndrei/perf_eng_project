#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef USE_PAPI
#include <papi.h>
#define REGION_BEGIN() PAPI_hl_region_begin("micro")
#define REGION_END()   PAPI_hl_region_end("micro")
#else
#define REGION_BEGIN() ((void)0)
#define REGION_END()   ((void)0)
#endif

#define LINE 64

static double now(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec * 1e-9;
}

static uint64_t rng_state = 88172645463325252ULL;
static uint64_t xorshift(void) {
  rng_state ^= rng_state << 13;
  rng_state ^= rng_state >> 7;
  rng_state ^= rng_state << 17;
  return rng_state;
}

__attribute__((noinline)) static int do_res(void) {
  struct timespec r;
  clock_getres(CLOCK_MONOTONIC, &r);
  printf("res CLOCK_MONOTONIC ns %ld\n", r.tv_nsec);
#ifdef CLOCK_PROCESS_CPUTIME_ID
  clock_getres(CLOCK_PROCESS_CPUTIME_ID, &r);
  printf("res CLOCK_PROCESS_CPUTIME_ID ns %ld\n", r.tv_nsec);
#endif
  const int calls = 1000000;
  double t0 = now(), sink = 0;
  for (int i = 0; i < calls; i++) sink += now();
  double t1 = now();
  printf("clock_gettime overhead ns %.1f (sink %g)\n", (t1 - t0) / calls * 1e9, sink > 0 ? 1.0 : 0.0);
  return 0;
}

__attribute__((noinline)) static int do_alu(long n) {
  uint64_t x = 1;
  double t0 = now();
  REGION_BEGIN();
  for (long i = 0; i < n; i++) {
    x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    __asm__ volatile("" : "+r"(x));
  }
  REGION_END();
  double t1 = now();
  printf("alu iterations %ld time_s %.6f ns_per_iter %.3f result %llu\n",
         n, t1 - t0, (t1 - t0) / n * 1e9, (unsigned long long)x);
  return 0;
}

typedef struct node { struct node *next; char pad[LINE - sizeof(struct node *)]; } node;

__attribute__((noinline)) static int do_chase(long size_kb, long steps) {
  size_t n = (size_t)size_kb * 1024 / sizeof(node);
  if (n < 2) { fprintf(stderr, "size too small\n"); return 1; }
  node *a;
  if (posix_memalign((void **)&a, 4096, n * sizeof(node))) { perror("alloc"); return 1; }
  size_t *perm = malloc(n * sizeof(size_t));
  for (size_t i = 0; i < n; i++) perm[i] = i;
  for (size_t i = n - 1; i > 0; i--) {
    size_t j = xorshift() % i;
    size_t t = perm[i]; perm[i] = perm[j]; perm[j] = t;
  }
  for (size_t i = 0; i < n; i++) a[i].next = &a[perm[i]];
  free(perm);
  node *p = &a[0];
  for (size_t i = 0; i < n; i++) p = p->next;
  double t0 = now();
  REGION_BEGIN();
  for (long i = 0; i < steps; i++) p = p->next;
  REGION_END();
  double t1 = now();
  printf("chase size_kb %ld steps %ld ns_per_load %.2f (end %p)\n",
         size_kb, steps, (t1 - t0) / steps * 1e9, (void *)p);
  free(a);
  return 0;
}

__attribute__((noinline)) static int do_mlp(long size_kb, long steps, int k) {
  size_t n = (size_t)size_kb * 1024 / sizeof(node);
  node *a;
  if (k < 1 || k > 64 || posix_memalign((void **)&a, 4096, n * sizeof(node))) return 1;
  size_t *perm = malloc(n * sizeof(size_t));
  for (size_t i = 0; i < n; i++) perm[i] = i;
  for (size_t i = n - 1; i > 0; i--) {
    size_t j = xorshift() % i;
    size_t t = perm[i]; perm[i] = perm[j]; perm[j] = t;
  }
  for (size_t i = 0; i < n; i++) a[i].next = &a[perm[i]];
  free(perm);
  node *p[64];
  for (int c = 0; c < k; c++) p[c] = &a[(n / k) * c];
  double t0 = now();
  for (long i = 0; i < steps; i++)
    for (int c = 0; c < k; c++) p[c] = p[c]->next;
  double t1 = now();
  uintptr_t x = 0;
  for (int c = 0; c < k; c++) x ^= (uintptr_t)p[c];
  printf("mlp size_kb %ld chains %d ns_per_load %.2f (x %lx)\n", size_kb, k,
         (t1 - t0) / ((double)steps * k) * 1e9, (unsigned long)x);
  free(a);
  return 0;
}

__attribute__((noinline)) static int do_read(long size_mb) {
  size_t n = (size_t)size_mb * 1024 * 1024 / sizeof(uint64_t);
  uint64_t *a = malloc(n * sizeof(uint64_t));
  for (size_t i = 0; i < n; i++) a[i] = i;
  uint64_t s = 0;
  double t0 = now();
  REGION_BEGIN();
  for (size_t i = 0; i < n; i++) s += a[i];
  REGION_END();
  double t1 = now();
  printf("read size_mb %ld GBps %.2f (sum %llu)\n", size_mb,
         n * sizeof(uint64_t) / (t1 - t0) / 1e9, (unsigned long long)s);
  free(a);
  return 0;
}

int main(int argc, char **argv) {
  if (argc >= 2 && !strcmp(argv[1], "res")) return do_res();
  if (argc >= 3 && !strcmp(argv[1], "alu")) return do_alu(atol(argv[2]));
  if (argc >= 4 && !strcmp(argv[1], "chase")) return do_chase(atol(argv[2]), atol(argv[3]));
  if (argc >= 3 && !strcmp(argv[1], "read")) return do_read(atol(argv[2]));
  if (argc >= 5 && !strcmp(argv[1], "mlp")) return do_mlp(atol(argv[2]), atol(argv[3]), atoi(argv[4]));
  fprintf(stderr, "usage: %s res | alu N | chase SIZE_KB STEPS | read SIZE_MB | mlp SIZE_KB STEPS K\n", argv[0]);
  return 2;
}
