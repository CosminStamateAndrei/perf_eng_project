#!/usr/bin/env python3
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RES = os.path.join(ROOT, "pe", "results")
FIG = os.path.join(ROOT, "report", "figures")
os.makedirs(FIG, exist_ok=True)
M = {"wsl": "Laptop (i7-12650H, WSL2)", "habrok": "Hábrók (2× EPYC 7763)"}
COL = {"wsl": "#1f77b4", "habrok": "#d62728"}
plt.rcParams.update({"font.size": 8, "axes.grid": True, "grid.alpha": 0.3, "savefig.bbox": "tight",
                     "figure.figsize": (3.4, 2.3), "legend.fontsize": 7})

def summ(m):
    return pd.read_csv(os.path.join(RES, m, "summary.csv"))

def latency():
    fig, ax = plt.subplots()
    for m in M:
        d = pd.read_csv(os.path.join(RES, m, "latency.csv"))
        d = d[d.core == d.core.iloc[0]]
        ax.plot(d.size_kb, d.ns_per_load, "o-", ms=3, color=COL[m], label=M[m])
    ax.set_xscale("log", base=2)
    ax.set_yscale("log")
    ax.set_xlabel("working set [KiB]")
    ax.set_ylabel("ns per dependent load")
    ax.legend()
    fig.savefig(os.path.join(FIG, "latency.pdf"))

def scaling():
    fig, axes = plt.subplots(1, 2, figsize=(7, 2.4))
    for ax, m in zip(axes, M):
        s = summ(m)
        for v, st in [("scaling-bound", "o-"), ("scaling-unbound", "s--")]:
            g = s[s.variant == v].sort_values("threads")
            ax.errorbar(g.threads, g.median_ms, yerr=[g.median_ms - g.q1_ms, g.q3_ms - g.median_ms],
                        fmt=st, ms=3, capsize=2, label=v.replace("scaling-", "threads "))
        ax.set_xscale("log", base=2)
        ax.set_yscale("log")
        ax.set_xlabel("OpenMP threads")
        ax.set_ylabel("ms per BFS (median, IQR)")
        ax.set_title(M[m])
        ax.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(FIG, "scaling.pdf"))

def optimisations():
    rows = [("O1 -O2", "O1-O2", None), ("O1 -O3 -march=native", "O1-native", None),
            ("O2 sched dynamic,256", "O2-sched", "dynamic;256"), ("O2 sched static,64", "O2-sched", "static;64"),
            ("O2 bind close", "O2-bind-close", None),
            ("O3 huge pages (madvise)", {"wsl": "O3-thp-madvise-huge", "habrok": "O3-thp-always-huge"}, None),
            ("O4 prefetch d=16", "O4-pf16", None), ("O5 degree relabel", "O5-relabel", None),
            ("O6 first touch + spread", {"wsl": "-", "habrok": "O6-k20-firsttouch"}, "spread")]
    fig, ax = plt.subplots(figsize=(7, 2.6))
    w = 0.38
    for j, m in enumerate(M):
        s = summ(m)
        base = s[(s.variant == "base") & (s.coreset == "all")].median_ms.iloc[0]
        sp = []
        for _, v, sch in rows:
            vv = v[m] if isinstance(v, dict) else v
            q = s[(s.variant == vv) & (s.coreset == "all")]
            if sch == "spread":
                q = q[q.bind == "spread"]
            elif sch:
                q = q[q.schedule == sch]
            sp.append(base / q.median_ms.iloc[0] if len(q) else np.nan)
        ax.bar(np.arange(len(rows)) + (j - 0.5) * w, sp, w, color=COL[m], label=M[m])
    ax.axhline(1, color="k", lw=0.8)
    ax.set_xticks(np.arange(len(rows)))
    ax.set_xticklabels([r[0] for r in rows], rotation=25, ha="right")
    ax.set_ylabel("speed-up vs baseline (median)")
    ax.legend()
    fig.savefig(os.path.join(FIG, "optimisations.pdf"))

def warmup():
    fig, ax = plt.subplots()
    for m in M:
        t = pd.read_csv(os.path.join(RES, m, "timings.csv"))
        w = t[t.variant == "base-warmup"]
        ax.plot(w.trial, w.time_s * 1e3, ".-", lw=0.6, ms=3, color=COL[m], label=M[m])
    ax.legend()
    ax.axvline(5.5, color="gray", ls=":")
    ax.set_yscale("log")
    ax.set_xlabel("trial index within one process")
    ax.set_ylabel("ms")
    fig.savefig(os.path.join(FIG, "warmup.pdf"))

def big_graphs():
    s = summ("habrok")
    rows = []
    for g, pre in [("kron20", ""), ("kron22", "big22-"), ("kron24", "big24-")]:
        for v in ["base", "relabel", "huge", "pf8"]:
            name = (pre + v) if pre else {"base": "base", "relabel": "O5-relabel",
                                          "huge": "O3-thp-always-huge", "pf8": "O4-pf8"}[v]
            q = s[(s.variant == name) & (s.coreset == "all")]
            if len(q):
                rows.append((g, v, q.gteps.iloc[0]))
    d = pd.DataFrame(rows, columns=["graph", "variant", "gteps"]).pivot(index="graph", columns="variant", values="gteps")
    ax = d[["base", "relabel", "huge", "pf8"]].plot.bar(figsize=(3.4, 2.3), rot=0)
    ax.set_ylabel("GTEPS (Hábrók, 128 threads)")
    ax.set_xlabel("")
    ax.figure.savefig(os.path.join(FIG, "big_graphs.pdf"))

for f in (latency, scaling, optimisations, warmup, big_graphs):
    try:
        f()
        print("ok", f.__name__)
    except Exception as e:
        print("FAILED", f.__name__, e)
mp = os.path.join(ROOT, "pe", "plots", "model", "model_vs_measured.pdf")
if os.path.exists(mp):
    import shutil
    shutil.copy(mp, os.path.join(FIG, "model.pdf"))
    print("ok model")
