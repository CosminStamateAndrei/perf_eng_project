ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OS=$(uname -s)
if [ -z "${MACHINE:-}" ]; then
  if [ "$OS" = Darwin ]; then MACHINE=mac; else MACHINE=x86; fi
fi
OUT=${OUT_DIR:-$ROOT/pe/results/$MACHINE}
RAW=$OUT/raw
BIN=$ROOT/pe/bin
GRAPH=${GRAPH:-$ROOT/kron20.sg}
mkdir -p "$OUT" "$RAW" "$BIN"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" | tee -a "$OUT/batch.log"; }

ncpu() { if command -v nproc >/dev/null 2>&1; then nproc; else sysctl -n hw.ncpu; fi; }

cpulist_count() {
  echo "$1" | tr ',' '\n' | awk -F- 'NF==2{n+=$2-$1+1; next} NF==1&&$1!=""{n++} END{print n+0}'
}

pcores() { cat /sys/devices/cpu_core/cpus 2>/dev/null || true; }
ecores() { cat /sys/devices/cpu_atom/cpus 2>/dev/null || true; }

nphys() {
  if [ "$OS" = Darwin ]; then sysctl -n hw.physicalcpu
  else lscpu -p=CORE 2>/dev/null | grep -v '^#' | sort -u | wc -l | tr -d ' '; fi
}

FAILED_STEPS=""
step() {
  local name=$1; shift
  if [ -n "${ONLY:-}" ] && ! echo " $ONLY " | grep -q " $name "; then return 0; fi
  log "=== START $name"
  local t0; t0=$(date +%s)
  if "$@" >> "$RAW/step_$name.log" 2>&1; then
    log "=== OK    $name ($(( $(date +%s) - t0 )) s)"
  else
    log "=== FAIL  $name (see raw/step_$name.log)"
    FAILED_STEPS="$FAILED_STEPS $name"
  fi
}
