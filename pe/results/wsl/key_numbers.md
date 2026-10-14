# Key numbers: wsl

Warm-up trials dropped per process: 5

## Baseline (kron20)

| core set | threads | median ms | IQR ms | GTEPS |
|---|---|---|---|---|
| all | 10 | 8.58 | 4.76 | 1.83 |

STREAM all: Copy 19.6 GB/s, Scale 15.0 GB/s, Add 15.4 GB/s, Triad 15.9 GB/s
STREAM P: Copy 19.7 GB/s, Scale 16.1 GB/s, Add 15.8 GB/s, Triad 16.2 GB/s
STREAM 1T: Copy 18.7 GB/s, Scale 11.1 GB/s, Add 12.1 GB/s, Triad 12.3 GB/s

## Load latency (pointer chase, ns)

P-core: 16KB 3.4, 32KB 3.4, 64KB 9.3, 128KB 9.4, 256KB 10.5, 512KB 8.2, 1024KB 15.2, 2048KB 41.4, 4096KB 57.4, 8192KB 165.7, 16384KB 187.0, 32768KB 210.7, 65536KB 186.2, 131072KB 229.9, 262144KB 303.3, 524288KB 325.1, 1048576KB 375.9

## timer_resolution.txt
```
res CLOCK_MONOTONIC ns 1
res CLOCK_PROCESS_CPUTIME_ID ns 1
clock_gettime overhead ns 36.1 (sink 1)
```

## sched_correctness.txt
```
static 8/8 PASS
static,1000 4/8 PASS
dynamic,100 0/8 PASS
guided 0/8 PASS
dynamic,64 8/8 PASS
dynamic,1024 8/8 PASS
```

## thp_usage.txt
```
never/base: THP Rss:              140736 kB THP AnonHugePages:         0 kB 
madvise/base: THP Rss:              140692 kB THP AnonHugePages:         0 kB 
madvise/huge: THP Rss:              140708 kB THP AnonHugePages:    126976 kB 
always/base: THP Rss:              140640 kB THP AnonHugePages:    126976 kB
```

## verify.txt
```
bfs_O0 PASS
bfs_O1 PASS
bfs_O2 PASS
bfs_O3 PASS
bfs_a15b18 PASS
bfs_a15b36 PASS
bfs_a15b9 PASS
bfs_a30b18 PASS
bfs_a30b36 PASS
bfs_a30b9 PASS
bfs_a5b18 PASS
bfs_a5b36 PASS
bfs_a5b9 PASS
bfs_base PASS
bfs_huge PASS
bfs_native PASS
bfs_pf16 PASS
bfs_pf2 PASS
bfs_pf32 PASS
bfs_pf4 PASS
bfs_pf8 PASS
bfs_pg PASS
bfs_relabel PASS
bfs_sched PASS
bfs_thp PASS
```

## Timer cross-check (one process, NTR trials)

| rep | GAPBS read+trials s | perf duration_time s | perf task-clock s | /usr/bin/time elapsed s |
|---|---|---|---|---|
| 1 | 0.679 | 0.717 | 6.000 | 0.69 |
| 2 | 1.308 | 1.320 | 12.508 | 1.31 |
| 3 | 1.098 | 1.112 | 10.098 | 1.11 |
| 4 | 0.936 | 0.948 | 8.676 | 0.94 |
| 5 | 1.125 | 1.143 | 10.613 | 1.13 |

## Counters (BFS only = n trials minus graph load)

| variant | event | per trial | per edge |
|---|---|---|---|
| base-all | context-switches | 0.9688 | 6.171e-08 |
| base-all | cpu-migrations | 0.000 | |
| base-all | page-faults | 23.7 | 1.51e-06 |
| base-all | task-clock | 1.631e+08 | 10.39 |
