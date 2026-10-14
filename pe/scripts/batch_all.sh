#!/usr/bin/env bash
set -u
export MACHINE=${MACHINE:-x86}
. "$(dirname "$0")/common.sh"
cd "$ROOT"

QUICK=${QUICK:-0}
if [ "$QUICK" = 1 ]; then
  export REPS=1 TRIALS=8; PSTAT_R=1; NTR=8; SKIP_APT=${SKIP_APT:-1}; SET_SYS=0
  OUT=$ROOT/pe/results/x86_quick; RAW=$OUT/raw; export OUT_DIR=$OUT; mkdir -p "$RAW"
else
  export REPS=${REPS:-5} TRIALS=${TRIALS:-24}; PSTAT_R=5; NTR=64; SKIP_APT=${SKIP_APT:-0}; SET_SYS=${SET_SYS:-1}
fi
export CSV=$OUT/timings.csv
PERF=$OUT/perf; mkdir -p "$PERF"
chmod +x "$ROOT"/pe/scripts/*.sh
RUN="$ROOT/pe/scripts/run_bfs.sh"
RUN_T=$RUN
[ "${NO_TIMING:-0}" = 1 ] && RUN=true
if command -v perf > /dev/null; then PSTAT="perf stat"; else PSTAT="$ROOT/pe/bin/pecount"; fi
log "batch_all start (QUICK=$QUICK) on $(hostname), kernel $(uname -r)"

P=$(pcores); E=$(ecores)
NLOG=$(ncpu); NPHYS=$(nphys)
[ -z "$P" ] && P="0-$((NLOG-1))"
P0=${P%%[-,]*}
E0=${E%%[-,]*}
NP=$(cpulist_count "$P")
log "logical CPUs $NLOG, physical cores $NPHYS, P-cores [$P] ($NP), E-cores [${E:-none}]"

G1="cycles,instructions,branches,branch-misses"
G2="cache-references,cache-misses,LLC-loads,LLC-load-misses"
G3="L1-dcache-loads,L1-dcache-load-misses,dTLB-loads,dTLB-load-misses"
G4="task-clock,page-faults,context-switches,cpu-migrations"

pstat() {
  local v=$1 b=$2 groups=$3 g i=0
  for g in $groups; do
    i=$((i+1))
    for n in 0 $NTR; do
      $PREFIX $PSTAT -x, -r "$PSTAT_R" -e "$g" -o "$PERF/${v}__g${i}__n${n}.csv" \
        -- "$b" -f "$GRAPH" -n "$n" > /dev/null
    done
  done
}
ALLG="$G1 $G2 $G3 $G4"

setup() {
  if [ "$SKIP_APT" != 1 ]; then
    add-apt-repository -y universe || true
    apt-get update
    apt-get install -y build-essential git curl numactl papi-tools libpapi-dev time
    apt-get install -y "linux-tools-$(uname -r)" linux-tools-common || apt-get install -y linux-tools-generic
  fi
  if [ "$SET_SYS" = 1 ]; then
    sysctl -w kernel.perf_event_paranoid=-1
    sysctl -w kernel.kptr_restrict=0
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do echo performance > "$f"; done 2>/dev/null || true
  fi
  command -v perf
}

sysinfo() {
  {
    echo "## date";  date
    echo "## uname"; uname -a
    echo "## os";    cat /etc/os-release
    echo "## lscpu"; lscpu
    echo "## lscpu -e"; lscpu -e
    echo "## P-cores"; pcores; echo "## E-cores"; ecores
    echo "## caches"; getconf -a | grep -i CACHE
    for d in /sys/devices/system/cpu/cpu0/cache/index*; do echo "$d: L$(cat $d/level) $(cat $d/type) $(cat $d/size) line=$(cat $d/coherency_line_size)"; done
    [ -n "$E0" ] && for d in /sys/devices/system/cpu/cpu$E0/cache/index*; do echo "E $d: L$(cat $d/level) $(cat $d/type) $(cat $d/size)"; done
    echo "## memory"; free -g; cat /proc/meminfo | head -5
    echo "## dmidecode memory"; dmidecode -t memory 2>/dev/null | grep -E 'Speed|Type:|Size' | sort | uniq -c
    echo "## THP"; cat /sys/kernel/mm/transparent_hugepage/enabled
    echo "## governor"; cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
    echo "## epp"; cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null
    echo "## max freq P/E (kHz)"; cat /sys/devices/system/cpu/cpu$P0/cpufreq/cpuinfo_max_freq 2>/dev/null; [ -n "$E0" ] && cat /sys/devices/system/cpu/cpu$E0/cpufreq/cpuinfo_max_freq
    echo "## compiler"; g++ --version | head -1; gcc -v 2>&1 | tail -1
    echo "## perf"; perf --version
    echo "## papi"; papi_version 2>/dev/null || true
    echo "## git"; git log --oneline -1
  } > "$OUT/system.txt" 2>&1
}

build_all() {
  bash pe/scripts/build_variants.sh
  [ -f "$GRAPH" ] || ./converter -g 20 -b "$GRAPH"
}

verify_all() {
  : > "$OUT/verify.txt"
  local b name res tmp; tmp=$(mktemp -d)
  for b in "$BIN"/bfs_*; do
    case "$b" in *.log) continue ;; esac
    name=$(basename "$b")
    res=$(cd "$tmp" && OMP_SCHEDULE=dynamic,1024 PAPI_OUTPUT_DIRECTORY=$tmp "$b" -f "$GRAPH" -n 3 -v 2>&1 | grep -c 'Verification:.*PASS')
    echo "$name $([ "$res" = 3 ] && echo PASS || echo FAIL)" | tee -a "$OUT/verify.txt"
  done
  rm -rf "$tmp"
  ! grep -q FAIL "$OUT/verify.txt"
}

baseline() {
  CORESET=all "$RUN" "$BIN/bfs_base" base
  if [ -n "$E" ]; then
    PREFIX="taskset -c $P" CORESET=P "$RUN" "$BIN/bfs_base" base
    PREFIX="taskset -c $E" CORESET=E "$RUN" "$BIN/bfs_base" base
  fi
  OMP_NUM_THREADS=$NPHYS OMP_PROC_BIND=close OMP_PLACES=cores CORESET=all "$RUN" "$BIN/bfs_base" base-1-per-core
  CORESET=all "$RUN" "$BIN/bfs_base" base-warmup 1 128
}

scaling() {
  local list t
  if [ "$NPHYS" -gt 32 ]; then
    list=$(printf '%s\n' 1 2 4 8 16 32 48 64 96 128 "$NPHYS" "$NLOG" | sort -n | uniq | awk -v m="$NLOG" '$1<=m')
  else
    list=$(printf '%s\n' 1 2 4 $(seq 6 2 "$NPHYS") "$NPHYS" "$NP" "$NLOG" | sort -n | uniq | awk -v m="$NLOG" '$1<=m')
  fi
  for t in $list; do
    OMP_NUM_THREADS=$t OMP_PROC_BIND=close OMP_PLACES=cores CORESET=all "$RUN" "$BIN/bfs_base" scaling-bound
    OMP_NUM_THREADS=$t CORESET=all "$RUN" "$BIN/bfs_base" scaling-unbound
  done
}

timers() {
  "$BIN/microbench" res > "$OUT/timer_resolution.txt"
  local r
  for r in $(seq 1 5); do
    $PSTAT -x, -e duration_time,task-clock -o "$OUT/timers_perf_$r.csv" -- \
      /usr/bin/time -f "%e %U %S" -o "$OUT/timers_time_$r.txt" \
      "$BIN/bfs_base" -f "$GRAPH" -n "$NTR" > "$OUT/timers_gapbs_$r.txt"
  done
}

counters_base() {
  PREFIX="" pstat base-all "$BIN/bfs_base" "$ALLG"
  PREFIX="taskset -c $P" pstat base-P "$BIN/bfs_base" "$G1 $G2 $G3"
  [ -n "$E" ] && PREFIX="taskset -c $E" pstat base-E "$BIN/bfs_base" "$G1 $G2 $G3"
  OMP_NUM_THREADS=1 PREFIX="taskset -c $P0" pstat base-1T "$BIN/bfs_base" "$G1 $G2"
}

profile() {
  perf record -F 4999 -g -o "$RAW/perf.data" -- "$BIN/bfs_base" -f "$GRAPH" -n "$NTR" > /dev/null
  perf report -i "$RAW/perf.data" --stdio --no-children --sort symbol --percent-limit 0.3 > "$OUT/perf_report_symbols.txt"
  perf report -i "$RAW/perf.data" --stdio --no-children --sort dso,symbol --percent-limit 0.3 -g none > "$OUT/perf_report_dso.txt"
  perf report -i "$RAW/perf.data" --stdio --no-children --sort cpu -g none > "$OUT/perf_report_cpu.txt"
  perf report -i "$RAW/perf.data" --stdio --children --sort symbol --percent-limit 1 -g caller > "$OUT/perf_report_callgraph.txt"
  timeout 300 perf annotate -i "$RAW/perf.data" --stdio --dsos bfs_base 2>/dev/null \
    | head -c 30000000 > "$OUT/perf_annotate_all.txt" || true
  taskset -c "$P" perf record -F 4999 -g -o "$RAW/perf_P.data" -- "$BIN/bfs_base" -f "$GRAPH" -n "$NTR" > /dev/null
  perf report -i "$RAW/perf_P.data" --stdio --no-children --sort symbol --percent-limit 0.3 > "$OUT/perf_report_symbols_P.txt"
}

gprof_run() {
  local tmp; tmp=$(mktemp -d)
  (cd "$tmp" && "$BIN/bfs_pg" -f "$GRAPH" -n "$NTR" > /dev/null && gprof -b "$BIN/bfs_pg" gmon.out > "$OUT/gprof.txt")
  rm -rf "$tmp"
  local tmp2; tmp2=$(mktemp -d)
  (cd "$tmp2" && CORESET=all "$RUN" "$BIN/bfs_pg" gprof-instrumented)
  rm -rf "$tmp2"
}

known_answer() {
  local f="$OUT/known_answer.txt" n
  : > "$f"
  for n in 500000000 1000000000; do
    echo "## alu $n" >> "$f"
    taskset -c "$P0" $PSTAT -x, -e instructions:u,cycles:u -o "$f.tmp" -- "$BIN/microbench" alu $n >> "$f" 2>&1
    cat "$f.tmp" >> "$f"
  done
  for n in 10000000 20000000; do
    echo "## chase 1048576KB $n" >> "$f"
    taskset -c "$P0" $PSTAT -x, -e cache-misses:u,LLC-load-misses:u,dTLB-load-misses:u,L1-dcache-load-misses:u -o "$f.tmp" -- "$BIN/microbench" chase 1048576 $n >> "$f" 2>&1
    cat "$f.tmp" >> "$f"
  done
  rm -f "$f.tmp"
  objdump -d --no-show-raw-insn "$BIN/microbench" | awk '/<do_alu>:/,/^$/' > "$OUT/known_answer_alu_disasm.txt"
}

latency() {
  local f="$OUT/latency.csv" kb core
  echo "core,size_kb,ns_per_load" > "$f"
  for core in P${P0} ${E0:+E$E0}; do
    for kb in 16 32 64 128 256 512 1024 2048 4096 8192 16384 32768 65536 131072 262144 524288 1048576; do
      taskset -c "${core#?}" "$BIN/microbench" chase $kb 10000000 \
        | awk -v c="${core%%[0-9]*}" '{print c","$3","$7}' >> "$f"
    done
  done
}

mlp() {
  local f="$OUT/mlp.csv" k
  echo "chains,ns_per_load" > "$f"
  for k in 1 2 4 6 8 10 12 16 20 24 32; do
    taskset -c "$P0" "$BIN/microbench" mlp 1048576 2000000 $k | awk '{print $5","$7}' >> "$f"
  done
}

stream() {
  OMP_NUM_THREADS=$NLOG "$BIN/stream" > "$OUT/stream_all.txt"
  OMP_NUM_THREADS=$NP taskset -c "$P" "$BIN/stream" > "$OUT/stream_P.txt"
  [ -n "$E" ] && OMP_NUM_THREADS=$(cpulist_count "$E") taskset -c "$E" "$BIN/stream" > "$OUT/stream_E.txt"
  OMP_NUM_THREADS=1 taskset -c "$P0" "$BIN/stream" > "$OUT/stream_1T.txt"
}

papi() {
  [ -x "$BIN/bfs_papi" ] || { echo "no bfs_papi"; return 1; }
  papi_avail -a > "$OUT/papi_avail.txt" 2>&1 || true
  papi_component_avail > "$OUT/papi_components.txt" 2>&1 || true
  local GEN="perf::PERF_COUNT_HW_CPU_CYCLES,perf::PERF_COUNT_HW_INSTRUCTIONS,perf::PERF_COUNT_HW_CACHE_REFERENCES,perf::PERF_COUNT_HW_CACHE_MISSES"
  local PRE="PAPI_TOT_CYC,PAPI_TOT_INS,PAPI_L2_DCM,PAPI_L3_TCM"
  local d
  d=$RAW/papi_1T; rm -rf "$d"
  OMP_NUM_THREADS=1 PAPI_EVENTS=$GEN PAPI_OUTPUT_DIRECTORY=$d taskset -c "$P0" "$BIN/bfs_papi" -f "$GRAPH" -n "$NTR" > "$OUT/papi_1T_stdout.txt"
  d=$RAW/papi_P_generic; rm -rf "$d"
  PAPI_EVENTS=$GEN PAPI_OUTPUT_DIRECTORY=$d taskset -c "$P" "$BIN/bfs_papi" -f "$GRAPH" -n "$NTR" > /dev/null
  d=$RAW/papi_P_preset; rm -rf "$d"
  PAPI_EVENTS=$PRE PAPI_OUTPUT_DIRECTORY=$d taskset -c "$P" "$BIN/bfs_papi" -f "$GRAPH" -n "$NTR" > /dev/null || true
  [ -x "$BIN/microbench_papi" ] && {
    d=$RAW/papi_micro_alu; rm -rf "$d"
    PAPI_EVENTS="perf::PERF_COUNT_HW_INSTRUCTIONS,perf::PERF_COUNT_HW_CPU_CYCLES" PAPI_OUTPUT_DIRECTORY=$d \
      taskset -c "$P0" "$BIN/microbench_papi" alu 500000000
    d=$RAW/papi_micro_chase; rm -rf "$d"
    PAPI_EVENTS="perf::PERF_COUNT_HW_CACHE_MISSES" PAPI_OUTPUT_DIRECTORY=$d \
      taskset -c "$P0" "$BIN/microbench_papi" chase 1048576 10000000
  }
  mkdir -p "$OUT/papi"; cp -r "$RAW"/papi_* "$OUT/papi/" 2>/dev/null || true
}

o1_compiler() {
  local v
  for v in O0 O1 O2 O3 native; do
    CORESET=all "$RUN" "$BIN/bfs_$v" "O1-$v"
    PREFIX="" pstat "O1-$v" "$BIN/bfs_$v" "$G1"
  done
}

o2_sched() {
  local s r
  : > "$OUT/sched_correctness.txt"
  for s in static "static,1000" "dynamic,100" guided "dynamic,64" "dynamic,1024"; do
    r=$(OMP_SCHEDULE=$s "$BIN/bfs_sched" -f "$GRAPH" -n 8 -v | grep -c 'Verification:.*PASS')
    echo "$s $r/8 PASS" >> "$OUT/sched_correctness.txt"
  done
  for s in "static,64" "static,1024" "dynamic,64" "dynamic,256" "dynamic,1024" "dynamic,4096"; do
    OMP_SCHEDULE=$s CORESET=all "$RUN" "$BIN/bfs_sched" O2-sched
    OMP_SCHEDULE=$s PREFIX="taskset -c $P" CORESET=P "$RUN" "$BIN/bfs_sched" O2-sched
  done
  OMP_PROC_BIND=close OMP_PLACES=cores CORESET=all "$RUN" "$BIN/bfs_base" O2-bind-close
  OMP_PROC_BIND=spread OMP_PLACES=cores CORESET=all "$RUN" "$BIN/bfs_base" O2-bind-spread
  OMP_NUM_THREADS=$NPHYS OMP_PROC_BIND=close OMP_PLACES=cores CORESET=all "$RUN" "$BIN/bfs_base" O2-1-per-core
}

thp_set() { [ "$SET_SYS" = 1 ] && echo "$1" > /sys/kernel/mm/transparent_hugepage/enabled; cat /sys/kernel/mm/transparent_hugepage/enabled; }
o3_hugepages() {
  local orig; orig=$(sed 's/.*\[\(.*\)\].*/\1/' /sys/kernel/mm/transparent_hugepage/enabled)
  local f="$OUT/thp_usage.txt"; : > "$f"
  if [ "$SET_SYS" != 1 ]; then
    echo "system THP mode: $orig" >> "$f"
    CORESET=all "$RUN" "$BIN/bfs_thp" "O3-thp-$orig-base"
    PREFIX="" pstat "O3-thp-$orig-base" "$BIN/bfs_thp" "$G3"
    echo "$orig/base: $("$BIN/bfs_thp" -f "$GRAPH" -n 1 | grep THP | tr '\n' ' ')" >> "$f"
    CORESET=all "$RUN" "$BIN/bfs_huge" "O3-thp-$orig-huge"
    PREFIX="" pstat "O3-thp-$orig-huge" "$BIN/bfs_huge" "$G3"
    echo "$orig/huge: $("$BIN/bfs_huge" -f "$GRAPH" -n 1 | grep THP | tr '\n' ' ')" >> "$f"
    return 0
  fi
  thp_set never
  CORESET=all "$RUN" "$BIN/bfs_thp" O3-thp-never
  PREFIX="" pstat O3-thp-never "$BIN/bfs_thp" "$G3"
  echo "never/base: $("$BIN/bfs_thp" -f "$GRAPH" -n 1 | grep THP | tr '\n' ' ')" >> "$f"
  thp_set madvise
  CORESET=all "$RUN" "$BIN/bfs_thp" O3-thp-madvise-base
  PREFIX="" pstat O3-thp-madvise-base "$BIN/bfs_thp" "$G3"
  echo "madvise/base: $("$BIN/bfs_thp" -f "$GRAPH" -n 1 | grep THP | tr '\n' ' ')" >> "$f"
  CORESET=all "$RUN" "$BIN/bfs_huge" O3-thp-madvise-huge
  PREFIX="" pstat O3-thp-madvise-huge "$BIN/bfs_huge" "$G3"
  echo "madvise/huge: $("$BIN/bfs_huge" -f "$GRAPH" -n 1 | grep THP | tr '\n' ' ')" >> "$f"
  thp_set always
  CORESET=all "$RUN" "$BIN/bfs_thp" O3-thp-always
  PREFIX="" pstat O3-thp-always "$BIN/bfs_thp" "$G3"
  echo "always/base: $("$BIN/bfs_thp" -f "$GRAPH" -n 1 | grep THP | tr '\n' ' ')" >> "$f"
  thp_set "$orig"
}

o4_prefetch() {
  local d
  for d in 2 4 8 16 32; do
    CORESET=all "$RUN" "$BIN/bfs_pf$d" "O4-pf$d"
    PREFIX="" pstat "O4-pf$d" "$BIN/bfs_pf$d" "$G1 $G2"
  done
}

o5_relabel() {
  CORESET=all "$RUN" "$BIN/bfs_relabel" O5-relabel
  PREFIX="" pstat O5-relabel "$BIN/bfs_relabel" "$G2 $G3"
}
alphabeta() {
  local a b
  for a in 5 15 30; do for b in 9 18 36; do
    CORESET=all "$RUN" "$BIN/bfs_a${a}b${b}" "AB-a${a}b${b}"
  done; done
  "$BIN/bfs_base" -f "$GRAPH" -n 1 -l > "$OUT/bfs_steps_log.txt"
}
big_graph() {
  local scales="22" s v
  [ "$NLOG" -ge 64 ] && scales="22 24"
  for s in $scales; do
    local G=$ROOT/kron$s.sg
    [ -f "$G" ] || ./converter -g $s -b "$G"
    for v in base huge pf8 relabel; do
      [ -x "$BIN/bfs_$v" ] && GRAPH=$G CORESET=all "$RUN" "$BIN/bfs_$v" "big$s-$v"
    done
    GRAPH=$G PREFIX="" pstat "big$s-base" "$BIN/bfs_base" "$G1 $G2 $G3"
  done
}

o6_first_touch() {
  [ -x "$BIN/bfs_ft" ] || { echo "no bfs_ft"; return 1; }
  lscpu | grep -i numa > "$OUT/numa_lscpu.txt"
  local s G
  for s in 20 22 24; do
    G=$ROOT/kron$s.sg; [ -f "$G" ] || continue
    GRAPH=$G CORESET=all "$RUN_T" "$BIN/bfs_base" "O6-k$s-base"
    GRAPH=$G CORESET=all "$RUN_T" "$BIN/bfs_ft" "O6-k$s-firsttouch"
    OMP_PROC_BIND=spread OMP_PLACES=cores GRAPH=$G CORESET=all "$RUN_T" "$BIN/bfs_base" "O6-k$s-base"
    OMP_PROC_BIND=spread OMP_PLACES=cores GRAPH=$G CORESET=all "$RUN_T" "$BIN/bfs_ft" "O6-k$s-firsttouch"
  done
}

numa() {
  command -v numactl >/dev/null || { echo "no numactl"; return 0; }
  local nodes; nodes=$(numactl -H | awk '/^available:/{print $2}')
  numactl -H > "$OUT/numa.txt"
  [ "${nodes:-1}" -gt 1 ] || { echo "single NUMA node"; return 0; }
  CORESET=all "$RUN" "$BIN/bfs_base" O6-numa-default
  PREFIX="numactl --interleave=all" CORESET=all "$RUN" "$BIN/bfs_base" O6-numa-interleave
  PREFIX="numactl --interleave=all" pstat O6-numa-interleave "$BIN/bfs_base" "$G1 $G2"
  OMP_PROC_BIND=spread OMP_PLACES=cores PREFIX="numactl --interleave=all" CORESET=all "$RUN" "$BIN/bfs_base" O6-numa-interleave-spread
  local s=22; [ -f "$ROOT/kron24.sg" ] && s=24
  GRAPH=$ROOT/kron$s.sg CORESET=all "$RUN" "$BIN/bfs_base" "big$s-numa-default"
  GRAPH=$ROOT/kron$s.sg PREFIX="numactl --interleave=all" CORESET=all "$RUN" "$BIN/bfs_base" "big$s-numa-interleave"
}

package() {
  rm -f "$RAW"/perf*.data*
  local tgz=$HOME/${MACHINE}_results_$(date +%H%M).tar.gz
  tar czf "$tgz" -C "$ROOT" "pe/results/$(basename "$OUT")"
  log "results archived to $tgz"
  git add "pe/results/$(basename "$OUT")"
  git -c user.name="batch" -c user.email="batch@localhost" commit -qm "x86 results $(date +%F_%H%M)" || true
  if [ -n "${GH_TOKEN:-}" ]; then
    local url; url=$(git remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#; s#^https://[^@]*@#https://#')
    git push "${url/https:\/\//https://x-access-token:${GH_TOKEN}@}" HEAD:master
  else
    log "GH_TOKEN not set: push manually or upload $tgz"
  fi
}

step setup setup
step sysinfo sysinfo
[ "${SKIP_BUILD:-0}" = 1 ] || step build build_all
step verify verify_all
step baseline baseline
step timers timers
step counters_base counters_base
step profile profile
step gprof gprof_run
step known_answer known_answer
step papi papi
step latency latency
step mlp mlp
step stream stream
step scaling scaling
step o1_compiler o1_compiler
step o2_sched o2_sched
step o3_hugepages o3_hugepages
step o4_prefetch o4_prefetch
step o5_relabel o5_relabel
step alphabeta alphabeta
[ "$QUICK" = 1 ] || step big_graph big_graph
[ "$QUICK" = 1 ] || step numa numa
step o6_first_touch o6_first_touch
[ "$QUICK" = 1 ] || step package package

log "batch_all done. Failed steps:${FAILED_STEPS:- none}"
