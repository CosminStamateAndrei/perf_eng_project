#!/usr/bin/env bash
set -u
export MACHINE=mac
. "$(dirname "$0")/common.sh"
cd "$ROOT"
export REPS=${REPS:-5} TRIALS=${TRIALS:-24}
export CSV=$OUT/timings.csv
chmod +x pe/scripts/*.sh
RUN="$ROOT/pe/scripts/run_bfs.sh"
NLOG=$(ncpu); NP=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo "$NLOG")
log "mac batch start: $NLOG CPUs, $NP P-cores"

sysinfo() {
  {
    sw_vers; uname -a
    sysctl -n machdep.cpu.brand_string
    sysctl hw.ncpu hw.physicalcpu hw.memsize hw.pagesize hw.cachelinesize \
           hw.l1dcachesize hw.l2cachesize hw.perflevel0.physicalcpu hw.perflevel1.physicalcpu \
           hw.perflevel0.l2cachesize hw.perflevel1.l2cachesize 2>/dev/null
    echo "## compiler"; ${CXX:-g++} --version | head -1
    echo "## power"; pmset -g batt | head -2; pmset -g | grep -i -E 'lowpowermode|powermode'
    git log --oneline -1
  } > "$OUT/system.txt" 2>&1
}
build_all() { bash pe/scripts/build_variants.sh && { [ -f "$GRAPH" ] || ./converter -g 20 -b "$GRAPH"; }; }
verify_all() {
  : > "$OUT/verify.txt"
  for b in "$BIN"/bfs_*; do
    case "$b" in *.log) continue ;; esac
    r=$(OMP_SCHEDULE=dynamic,1024 "$b" -f "$GRAPH" -n 3 -v | grep -c 'Verification:.*PASS')
    echo "$(basename "$b") $([ "$r" = 3 ] && echo PASS || echo FAIL)" | tee -a "$OUT/verify.txt"
  done
  ! grep -q FAIL "$OUT/verify.txt"
}
baseline() {
  CORESET=all "$RUN" "$BIN/bfs_base" base
  OMP_NUM_THREADS=$NP CORESET=Pcount "$RUN" "$BIN/bfs_base" base
  CORESET=all "$RUN" "$BIN/bfs_base" base-warmup 1 128
}
scaling() {
  for t in $(printf '%s\n' 1 2 4 6 8 "$NP" 10 12 14 16 "$NLOG" | sort -n | uniq | awk -v m="$NLOG" '$1<=m'); do
    OMP_NUM_THREADS=$t CORESET=all "$RUN" "$BIN/bfs_base" scaling-unbound
  done
}
timers() {
  "$BIN/microbench" res > "$OUT/timer_resolution.txt"
  for r in 1 2 3 4 5; do
    /usr/bin/time -l "$BIN/bfs_base" -f "$GRAPH" -n 64 > "$OUT/timers_gapbs_$r.txt" 2> "$OUT/timers_time_$r.txt"
  done
}
latency() {
  echo "core,size_kb,ns_per_load" > "$OUT/latency.csv"
  for kb in 16 32 64 128 256 512 1024 2048 4096 8192 16384 32768 65536 131072 262144 524288 1048576; do
    "$BIN/microbench" chase $kb 10000000 | awk '{print "any,"$3","$7}' >> "$OUT/latency.csv"
  done
}
stream() {
  OMP_NUM_THREADS=$NLOG "$BIN/stream" > "$OUT/stream_all.txt"
  OMP_NUM_THREADS=$NP "$BIN/stream" > "$OUT/stream_P.txt"
  OMP_NUM_THREADS=1 "$BIN/stream" > "$OUT/stream_1T.txt"
}
known_answer() {
  "$BIN/microbench" alu 1000000000 > "$OUT/known_answer.txt"
  "$BIN/microbench" chase 1048576 10000000 >> "$OUT/known_answer.txt"
  otool -tvV "$BIN/microbench" | awk '/_do_alu:/,/^_do_chase:/' > "$OUT/known_answer_alu_disasm.txt"
}
o1() { for v in O0 O1 O2 O3 native; do CORESET=all "$RUN" "$BIN/bfs_$v" "O1-$v"; done; }
o2() {
  : > "$OUT/sched_correctness.txt"
  for s in static "static,1000" "dynamic,100" guided "dynamic,64" "dynamic,1024"; do
    r=$(OMP_SCHEDULE=$s "$BIN/bfs_sched" -f "$GRAPH" -n 8 -v | grep -c 'Verification:.*PASS')
    echo "$s $r/8 PASS" >> "$OUT/sched_correctness.txt"
  done
  for s in "static,64" "static,1024" "dynamic,64" "dynamic,256" "dynamic,1024" "dynamic,4096"; do
    OMP_SCHEDULE=$s CORESET=all "$RUN" "$BIN/bfs_sched" O2-sched
  done
}
o4() { for d in 2 4 8 16 32; do CORESET=all "$RUN" "$BIN/bfs_pf$d" "O4-pf$d"; done; }
o5() {
  CORESET=all "$RUN" "$BIN/bfs_relabel" O5-relabel
  for a in 5 15 30; do for b in 9 18 36; do CORESET=all "$RUN" "$BIN/bfs_a${a}b${b}" "AB-a${a}b${b}"; done; done
  "$BIN/bfs_base" -f "$GRAPH" -n 1 -l > "$OUT/bfs_steps_log.txt"
}
big() {
  [ -f "$ROOT/kron22.sg" ] || ./converter -g 22 -b "$ROOT/kron22.sg"
  for v in base pf8 relabel; do GRAPH=$ROOT/kron22.sg CORESET=all "$RUN" "$BIN/bfs_$v" "big-$v"; done
}

step sysinfo sysinfo
step build build_all
step verify verify_all
step baseline baseline
step timers timers
step known_answer known_answer
step latency latency
step stream stream
step scaling scaling
step o1_compiler o1
step o2_sched o2
step o4_prefetch o4
step o5_relabel_ab o5
step big_graph big
log "mac batch done. Failed steps:${FAILED_STEPS:- none}"
