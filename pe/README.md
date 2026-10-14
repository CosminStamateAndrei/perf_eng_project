# pe

## Build

```
bash pe/scripts/build_variants.sh
```

## x86 (Linux)

```
sudo -i
git clone https://github.com/CosminStamateAndrei/gapbs.git && cd gapbs
GH_TOKEN=<token> bash pe/scripts/batch_all.sh 2>&1 | tee /root/batch.out
```

Smoke test (WSL):

```
QUICK=1 bash pe/scripts/batch_all.sh
```

## Mac

```
brew install gcc
git clone https://github.com/CosminStamateAndrei/gapbs.git && cd gapbs
CXX=g++-15 CC=gcc-15 bash pe/scripts/mac_all.sh
```

```
xcrun xctrace record --template 'Time Profiler' --output pe/results/mac/bfs_time.trace --launch -- pe/bin/bfs_base -f kron20.sg -n 64
```

## Analysis

```
git pull
python3 pe/scripts/analyze.py
```
