#define _GNU_SOURCE
#include <errno.h>
#include <linux/perf_event.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define MAXEV 32

typedef struct { const char *name; uint32_t type; uint64_t config; } evdef;

#define HWC(c, op, res) (PERF_COUNT_HW_CACHE_##c | (PERF_COUNT_HW_CACHE_OP_##op << 8) | \
                         (PERF_COUNT_HW_CACHE_RESULT_##res << 16))
static const evdef defs[] = {
  {"cycles", PERF_TYPE_HARDWARE, PERF_COUNT_HW_CPU_CYCLES},
  {"instructions", PERF_TYPE_HARDWARE, PERF_COUNT_HW_INSTRUCTIONS},
  {"branches", PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_INSTRUCTIONS},
  {"branch-misses", PERF_TYPE_HARDWARE, PERF_COUNT_HW_BRANCH_MISSES},
  {"cache-references", PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_REFERENCES},
  {"cache-misses", PERF_TYPE_HARDWARE, PERF_COUNT_HW_CACHE_MISSES},
  {"L1-dcache-loads", PERF_TYPE_HW_CACHE, HWC(L1D, READ, ACCESS)},
  {"L1-dcache-load-misses", PERF_TYPE_HW_CACHE, HWC(L1D, READ, MISS)},
  {"LLC-loads", PERF_TYPE_HW_CACHE, HWC(LL, READ, ACCESS)},
  {"LLC-load-misses", PERF_TYPE_HW_CACHE, HWC(LL, READ, MISS)},
  {"dTLB-loads", PERF_TYPE_HW_CACHE, HWC(DTLB, READ, ACCESS)},
  {"dTLB-load-misses", PERF_TYPE_HW_CACHE, HWC(DTLB, READ, MISS)},
  {"task-clock", PERF_TYPE_SOFTWARE, PERF_COUNT_SW_TASK_CLOCK},
  {"page-faults", PERF_TYPE_SOFTWARE, PERF_COUNT_SW_PAGE_FAULTS},
  {"context-switches", PERF_TYPE_SOFTWARE, PERF_COUNT_SW_CONTEXT_SWITCHES},
  {"cpu-migrations", PERF_TYPE_SOFTWARE, PERF_COUNT_SW_CPU_MIGRATIONS},
};

static long peo(struct perf_event_attr *a, pid_t pid) {
  return syscall(__NR_perf_event_open, a, pid, -1, -1, 0);
}

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec + t.tv_nsec * 1e-9;
}

int main(int argc, char **argv) {
  int reps = 1, ai;
  char *evs = NULL, *outf = NULL;
  for (ai = 1; ai < argc; ai++) {
    if (!strcmp(argv[ai], "--")) { ai++; break; }
    else if (!strncmp(argv[ai], "-x", 2)) continue;
    else if (!strcmp(argv[ai], "-r") && ai + 1 < argc) reps = atoi(argv[++ai]);
    else if (!strcmp(argv[ai], "-e") && ai + 1 < argc) evs = argv[++ai];
    else if (!strcmp(argv[ai], "-o") && ai + 1 < argc) outf = argv[++ai];
    else break;
  }
  if (!evs || ai >= argc) {
    fprintf(stderr, "usage: pecount [-x,] [-r N] -e ev,... [-o file] -- cmd args\n");
    return 2;
  }
  char *names[MAXEV]; int nev = 0;
  for (char *tok = strtok(evs, ","); tok && nev < MAXEV; tok = strtok(NULL, ",")) {
    char *c = strchr(tok, ':'); if (c) *c = 0;
    names[nev++] = tok;
  }
  double sum[MAXEV] = {0}, sum2[MAXEV] = {0}, run_pct[MAXEV] = {0};
  int supported[MAXEV];
  for (int e = 0; e < nev; e++) supported[e] = 1;

  for (int r = 0; r < reps; r++) {
    int go[2];
    if (pipe(go)) { perror("pipe"); return 1; }
    pid_t pid = fork();
    if (pid == 0) {
      char c; close(go[1]);
      if (read(go[0], &c, 1) < 0) _exit(127);
      execvp(argv[ai], &argv[ai]);
      perror("execvp"); _exit(127);
    }
    close(go[0]);
    int fd[MAXEV];
    for (int e = 0; e < nev; e++) {
      fd[e] = -1;
      if (!strcmp(names[e], "duration_time")) continue;
      const evdef *d = NULL;
      for (size_t k = 0; k < sizeof(defs) / sizeof(defs[0]); k++)
        if (!strcmp(defs[k].name, names[e])) d = &defs[k];
      if (!d) { supported[e] = 0; continue; }
      struct perf_event_attr a;
      memset(&a, 0, sizeof(a));
      a.size = sizeof(a); a.type = d->type; a.config = d->config;
      a.disabled = 1; a.enable_on_exec = 1; a.inherit = 1;
      a.exclude_kernel = (d->type != PERF_TYPE_SOFTWARE); a.exclude_hv = 1;
      a.read_format = PERF_FORMAT_TOTAL_TIME_ENABLED | PERF_FORMAT_TOTAL_TIME_RUNNING;
      fd[e] = (int)peo(&a, pid);
      if (fd[e] < 0 && !a.exclude_kernel) { a.exclude_kernel = 1; fd[e] = (int)peo(&a, pid); }
      if (fd[e] < 0) supported[e] = 0;
    }
    double t0 = now();
    if (write(go[1], "g", 1) < 0) perror("write");
    close(go[1]);
    int st;
    waitpid(pid, &st, 0);
    double dt = now() - t0;
    for (int e = 0; e < nev; e++) {
      double v = NAN;
      if (!strcmp(names[e], "duration_time")) { v = dt * 1e9; run_pct[e] += 100; }
      else if (fd[e] >= 0) {
        uint64_t buf[3];
        if (read(fd[e], buf, sizeof(buf)) == sizeof(buf) && buf[2] > 0) {
          v = (double)buf[0] * ((double)buf[1] / (double)buf[2]);
          run_pct[e] += 100.0 * buf[2] / (buf[1] ? buf[1] : 1);
        }
        close(fd[e]);
      }
      sum[e] += v; sum2[e] += v * v;
    }
    if (!WIFEXITED(st) || WEXITSTATUS(st)) fprintf(stderr, "pecount: command failed\n");
  }
  FILE *o = outf ? fopen(outf, "w") : stderr;
  if (!o) { perror(outf); return 1; }
  fprintf(o, "# pecount (perf_event_open; HW events user-space only), %d run(s)\n\n", reps);
  for (int e = 0; e < nev; e++) {
    if (!supported[e] || isnan(sum[e])) { fprintf(o, "<not supported>,,%s,,,\n", names[e]); continue; }
    double m = sum[e] / reps, var = sum2[e] / reps - m * m;
    double sd = reps > 1 && m > 0 ? 100.0 * sqrt(var > 0 ? var : 0) / m : 0;
    fprintf(o, "%.0f,,%s,%.2f,,%.2f\n", m, names[e], sd, run_pct[e] / reps);
  }
  if (outf) fclose(o);
  return 0;
}
