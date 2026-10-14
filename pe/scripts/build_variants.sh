#!/usr/bin/env bash
set -u
. "$(dirname "$0")/common.sh"
cd "$ROOT"

CXX=${CXX:-g++}
CC=${CC:-gcc}
BASE="-std=c++11 -Wall -g -fno-omit-frame-pointer -fopenmp"
case "$(uname -m)" in x86_64) NATIVE="-march=native" ;; *) NATIVE="-mcpu=native" ;; esac
FAIL=0

build() {
  local name=$1; shift
  printf '  %-14s %s %s\n' "$name" "$*" "${LIBS:-}"
  if ! $CXX $BASE "$@" src/bfs.cc -o "$BIN/$name" ${LIBS:-} 2> "$BIN/$name.log"; then
    echo "  !! BUILD FAILED: $name (see pe/bin/$name.log)"; FAIL=1
  fi
}

echo "Compiler: $($CXX --version | head -1)"
build bfs_base -O3
build bfs_O0 -O0
build bfs_O1 -O1
build bfs_O2 -O2
build bfs_O3 -O3
build bfs_native -O3 $NATIVE
build bfs_sched -O3 -DOMP_RUNTIME_SCHED
for d in 2 4 8 16 32; do build bfs_pf$d -O3 -DPF_DIST=$d; done
build bfs_relabel -O3 -DRELABEL
for a in 5 15 30; do
  for b in 9 18 36; do build bfs_a${a}b${b} -O3 -DBFS_ALPHA=$a -DBFS_BETA=$b; done
done

if [ "$OS" = Linux ]; then
  build bfs_thp -O3 -DPE_THP_REPORT
  build bfs_huge -O3 -DUSE_HUGEPAGES -DPE_THP_REPORT
  build bfs_pg -O3 -pg
  build bfs_ft -O3 -DPAR_FIRST_TOUCH
  $CC -O2 -o "$BIN/pecount" pe/bench/pecount.c -lm || FAIL=1
  if echo '#include <papi.h>' | $CXX -E -x c++ - > /dev/null 2>&1; then
    HAVE_PAPI=1
    LIBS=-lpapi build bfs_papi -O3 -DUSE_PAPI
  else
    echo "  (papi.h not found: skipping bfs_papi; install libpapi-dev or module load PAPI)"
  fi
fi

for v in O3 native; do
  flags="-O3"; [ $v = native ] && flags="-O3 $NATIVE"
  $CXX $BASE $flags -fopt-info-vec-all src/bfs.cc -o /dev/null 2> "$OUT/vec_report_${v}_full.txt"
  grep 'bfs.cc' "$OUT/vec_report_${v}_full.txt" > "$OUT/vec_report_${v}_bfs.txt" || true
done

$CXX $BASE -O3 src/converter.cc -o "$ROOT/converter" || FAIL=1

$CC -O2 -g -o "$BIN/microbench" pe/bench/microbench.c || FAIL=1
if [ "${HAVE_PAPI:-0}" = 1 ]; then
  $CC -O2 -g -DUSE_PAPI -o "$BIN/microbench_papi" pe/bench/microbench.c -lpapi || FAIL=1
fi

if [ ! -f pe/bench/stream.c ]; then
  curl -fsSL -o pe/bench/stream.c https://www.cs.virginia.edu/stream/FTP/Code/stream.c \
    || echo "  !! could not download stream.c"
fi
if [ -f pe/bench/stream.c ]; then
  $CC -O3 $NATIVE -fopenmp -DSTREAM_ARRAY_SIZE=40000000 -DNTIMES=20 \
      pe/bench/stream.c -o "$BIN/stream" || FAIL=1
fi

[ $FAIL = 0 ] && echo "All builds OK" || { echo "Some builds failed"; exit 1; }
