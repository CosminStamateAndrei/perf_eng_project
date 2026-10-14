#!/usr/bin/env bash
set -e
V=7.1.0
PREFIX=$HOME/opt/papi
mkdir -p "$HOME/src" && cd "$HOME/src"
if [ ! -f papi-$V.tar.gz ]; then
  curl -fL -o papi-$V.tar.gz https://icl.utk.edu/projects/papi/downloads/papi-$V.tar.gz \
  || curl -fL -o papi-$V.tar.gz https://github.com/icl-utk-edu/papi/releases/download/papi-7-1-0-t/papi-$V.tar.gz
fi
rm -rf papi-$V && tar xzf papi-$V.tar.gz && cd papi-$V/src
./configure --prefix="$PREFIX" > configure.log
make -j8 > make.log 2>&1 || { tail -30 make.log; exit 1; }
make install > install.log
echo "PAPI installed in $PREFIX"
"$PREFIX/bin/papi_avail" | head -30
