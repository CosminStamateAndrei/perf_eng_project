# Key numbers: habrok

Warm-up trials dropped per process: 5

## Baseline (kron20)

| core set | threads | median ms | IQR ms | GTEPS |
|---|---|---|---|---|
| all | 128 | 2.85 | 1.43 | 5.51 |

STREAM all: Copy 407.6 GB/s, Scale 300.8 GB/s, Add 339.6 GB/s, Triad 327.0 GB/s
STREAM P: Copy 313.3 GB/s, Scale 236.1 GB/s, Add 254.8 GB/s, Triad 250.2 GB/s
STREAM 1T: Copy 45.4 GB/s, Scale 34.7 GB/s, Add 34.7 GB/s, Triad 34.7 GB/s

## Load latency (pointer chase, ns)

P-core: 16KB 1.3, 32KB 1.4, 64KB 3.9, 128KB 3.5, 256KB 4.2, 512KB 9.0, 1024KB 13.9, 2048KB 12.1, 4096KB 13.0, 8192KB 13.4, 16384KB 13.6, 32768KB 15.2, 65536KB 64.2, 131072KB 85.2, 262144KB 91.8, 524288KB 96.9, 1048576KB 98.7

## timer_resolution.txt
```
res CLOCK_MONOTONIC ns 1
res CLOCK_PROCESS_CPUTIME_ID ns 1
clock_gettime overhead ns 33.5 (sink 1)
```

## sched_correctness.txt
```
static 8/8 PASS
static,1000 0/8 PASS
dynamic,100 0/8 PASS
guided 0/8 PASS
dynamic,64 8/8 PASS
dynamic,1024 8/8 PASS
```

## thp_usage.txt
```
system THP mode: always
always/base: THP Rss:              144400 kB THP AnonHugePages:    129024 kB 
always/huge: THP Rss:              142652 kB THP AnonHugePages:    126976 kB
```

## verify.txt
```
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
bfs_ft PASS
bfs_huge PASS
bfs_native PASS
bfs_O0 PASS
bfs_O1 PASS
bfs_O2 PASS
bfs_O3 PASS
bfs_papi PASS
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
| 1 | 0.000 | 0.005 | nan | n/a |
| 2 | 0.000 | 0.003 | nan | n/a |
| 3 | 0.000 | 0.002 | nan | n/a |
| 4 | 0.000 | 0.003 | nan | n/a |
| 5 | 0.000 | 0.003 | nan | n/a |

## Counters (BFS only = n trials minus graph load)

| variant | event | per trial | per edge |
|---|---|---|---|
| base-1T | LLC-load-misses | nan | nan |
| base-1T | LLC-loads | nan | nan |
| base-1T | branch-misses | 2.299e+06 | 0.1464 |
| base-1T | branches | 1.778e+07 | 1.133 |
| base-1T | cache-misses | 7.611e+05 | 0.04848 |
| base-1T | cache-references | 6.092e+06 | 0.3881 |
| base-1T | cycles | 8.669e+07 | 5.522 |
| base-1T | instructions | 8.397e+07 | 5.349 |
| base-P | L1-dcache-load-misses | 3.428e+06 | 0.2183 |
| base-P | L1-dcache-loads | 6.514e+07 | 4.149 |
| base-P | LLC-load-misses | nan | nan |
| base-P | LLC-loads | nan | nan |
| base-P | branch-misses | 2.273e+06 | 0.1448 |
| base-P | branches | 8.012e+07 | 5.103 |
| base-P | cache-misses | 1.609e+06 | 0.1025 |
| base-P | cache-references | 4.31e+06 | 0.2745 |
| base-P | cycles | 2.657e+09 | 169.2 |
| base-P | dTLB-load-misses | 3996 | 0.0002545 |
| base-P | dTLB-loads | 5.66e+04 | 0.003605 |
| base-P | instructions | 3.034e+08 | 19.33 |
| base-all | L1-dcache-load-misses | 3.483e+06 | 0.2218 |
| base-all | L1-dcache-loads | 7.433e+07 | 4.735 |
| base-all | LLC-load-misses | nan | nan |
| base-all | LLC-loads | nan | nan |
| base-all | branch-misses | 2.234e+06 | 0.1423 |
| base-all | branches | 6.805e+07 | 4.334 |
| base-all | cache-misses | 1.635e+06 | 0.1041 |
| base-all | cache-references | 4.536e+06 | 0.2889 |
| base-all | context-switches | 0 | 0 |
| base-all | cpu-migrations | 0.000 | |
| base-all | cycles | 2.246e+09 | 143.1 |
| base-all | dTLB-load-misses | 5275 | 0.000336 |
| base-all | dTLB-loads | 6.197e+04 | 0.003947 |
| base-all | instructions | 2.611e+08 | 16.63 |
| base-all | page-faults | 34.86 | 2.22e-06 |
| base-all | task-clock | 8.252e+08 | 52.56 |
| base-1T | all/IPC | 0.969 | |
| base-1T | all/cache-misses ratio | 0.125 | |
| base-1T | all/branch-misses ratio | 0.129 | |
| base-P | all/IPC | 0.114 | |
| base-P | all/cache-misses ratio | 0.373 | |
| base-P | all/dTLB-load-misses ratio | 0.071 | |
| base-P | all/L1-dcache-load-misses ratio | 0.053 | |
| base-P | all/branch-misses ratio | 0.028 | |
| base-all | all/IPC | 0.116 | |
| base-all | all/cache-misses ratio | 0.360 | |
| base-all | all/dTLB-load-misses ratio | 0.085 | |
| base-all | all/L1-dcache-load-misses ratio | 0.047 | |
| base-all | all/branch-misses ratio | 0.033 | |
