#!/usr/bin/env bash
set -u
. "$(dirname "$0")/common.sh"

BINARY=$1; VARIANT=$2; REPS=${3:-${REPS:-5}}; TRIALS=${4:-${TRIALS:-24}}
CSV=${CSV:-$OUT/timings.csv}
PREFIX=${PREFIX:-}
CORESET=${CORESET:-all}
GNAME=$(basename "$GRAPH" .sg); GNAME=$(basename "$GNAME" .wsg)

if [ -n "${OMP_NUM_THREADS:-}" ]; then THREADS=$OMP_NUM_THREADS
elif [ -n "$PREFIX" ]; then THREADS=$($PREFIX nproc 2>/dev/null || ncpu)
else THREADS=$(ncpu); fi

[ -f "$CSV" ] || echo "machine,variant,graph,edges,coreset,threads,bind,places,schedule,rep,trial,time_s" > "$CSV"

$PREFIX "$BINARY" -f "$GRAPH" -n 4 > /dev/null 2>&1 || { echo "run failed: $BINARY" >&2; exit 1; }

for rep in $(seq 1 "$REPS"); do
  out=$($PREFIX "$BINARY" -f "$GRAPH" -n "$TRIALS" 2>&1) || { echo "run failed: $BINARY" >&2; echo "$out" >&2; exit 1; }
  edges=$(echo "$out" | awk '/^Graph has/{print $6; exit}')
  echo "$out" | awk -v m="$MACHINE" -v v="$VARIANT" -v g="$GNAME" -v e="$edges" \
      -v c="$CORESET" -v t="$THREADS" -v b="${OMP_PROC_BIND:-none}" \
      -v p="${OMP_PLACES:-none}" -v s="${OMP_SCHEDULE:-default}" -v r="$rep" \
      '/^Trial Time:/{n++; gsub(",", ";", s); printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%d,%s\n", m,v,g,e,c,t,b,p,s,r,n,$3}' >> "$CSV"
done
med=$(awk -F, -v v="$VARIANT" -v c="$CORESET" -v t="$THREADS" -v s="${OMP_SCHEDULE:-default}" \
  'BEGIN{gsub(",",";",s)} $2==v && $5==c && $6==t && $9==s && $11>4 {print $12*1000}' "$CSV" \
  | sort -n | awk '{a[NR]=$1} END{if(NR) printf "%.2f", a[int((NR+1)/2)]; else print "n/a"}')
echo "  $VARIANT [$CORESET, $THREADS thr, sched=${OMP_SCHEDULE:-default}] median ${med} ms/trial"
