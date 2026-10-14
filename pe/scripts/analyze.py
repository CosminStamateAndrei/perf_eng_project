#!/usr/bin/env python3
import csv
import glob
import json
import os
import re
import sys
from collections import defaultdict

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WARM = 5
NTR_FULL = 64

plt.rcParams.update({"figure.figsize": (6.4, 3.6), "axes.grid": True, "grid.alpha": 0.3,
                     "font.size": 9, "savefig.bbox": "tight"})

def q(x, p):
    return float(np.percentile(x, p)) if len(x) else float("nan")

def summarize(tim):
    keys = ["machine", "variant", "graph", "edges", "coreset", "threads", "bind", "places", "schedule"]
    t = tim[tim.trial > WARM]
    rows = []
    for k, g in t.groupby(keys, sort=False):
        ms = g.time_s.values * 1e3
        med = np.median(ms)
        r = dict(zip(keys, k))
        r.update(n=len(ms), median_ms=med, q1_ms=q(ms, 25), q3_ms=q(ms, 75),
                 iqr_ms=q(ms, 75) - q(ms, 25), min_ms=ms.min(), max_ms=ms.max(),
                 gteps=r["edges"] / (med / 1e3) / 1e9)
        rows.append(r)
    return pd.DataFrame(rows)

def ref_median(s, variant="base", coreset="all"):
    m = s[(s.variant == variant) & (s.coreset == coreset)]
    return float(m.median_ms.iloc[0]) if len(m) else float("nan")

def bar(s, title, fname, outdir, label=lambda r: r.variant, ref=None):
    if s.empty:
        return
    fig, ax = plt.subplots()
    x = np.arange(len(s))
    err = np.vstack([s.median_ms - s.q1_ms, s.q3_ms - s.median_ms])
    ax.bar(x, s.median_ms, yerr=err, capsize=3, color="#4c72b0")
    if ref is not None and not np.isnan(ref):
        ax.axhline(ref, color="#c44e52", ls="--", lw=1, label=f"baseline {ref:.2f} ms")
        ax.legend()
    ax.set_xticks(x)
    ax.set_xticklabels([label(r) for r in s.itertuples()], rotation=35, ha="right")
    ax.set_ylabel("ms per BFS trial (median, IQR)")
    ax.set_title(title)
    fig.savefig(os.path.join(outdir, fname))
    plt.close(fig)

def plots_timings(tim, s, outdir):
    base = ref_median(s)
    w = tim[tim.variant == "base-warmup"]
    if not w.empty:
        fig, ax = plt.subplots()
        ax.plot(w.trial, w.time_s * 1e3, ".-", lw=0.8)
        ax.set_xlabel("trial index within one process")
        ax.set_ylabel("ms")
        ax.set_yscale("log")
        ax.set_title("Per-trial time: warm-up and outliers")
        fig.savefig(os.path.join(outdir, "warmup.pdf"))
        plt.close(fig)
    bar(s[s.variant == "base"], "Baseline by core set", "baseline_coresets.pdf", outdir,
        label=lambda r: f"{r.coreset} ({r.threads} thr)")
    sc = s[s.variant.str.startswith("scaling")]
    if not sc.empty:
        fig, ax = plt.subplots()
        for v, g in sc.groupby("variant"):
            g = g.sort_values("threads")
            t1 = g[g.threads == g.threads.min()].median_ms.iloc[0]
            ax.plot(g.threads, t1 / g.median_ms, "o-", label=v.replace("scaling-", ""))
        lim = sc.threads.max()
        ax.plot([1, lim], [1, lim], ":", color="gray", label="ideal")
        ax.set_xlabel("OpenMP threads")
        ax.set_ylabel("speed-up vs 1 thread")
        ax.set_title("Thread scaling")
        ax.legend()
        fig.savefig(os.path.join(outdir, "scaling.pdf"))
        plt.close(fig)
    bar(s[s.variant.str.startswith("O1-")], "O1: compiler optimisation level", "o1_compiler.pdf", outdir,
        label=lambda r: r.variant[3:], ref=base)
    o2 = s[s.variant.str.startswith("O2-")]
    bar(o2, "O2: OpenMP schedule / binding", "o2_openmp.pdf", outdir,
        label=lambda r: (r.schedule.replace(";", ",") if r.variant == "O2-sched" else r.variant[3:]) + f" [{r.coreset}]",
        ref=base)
    bar(s[s.variant.str.startswith("O3-")], "O3: transparent huge pages", "o3_hugepages.pdf", outdir,
        label=lambda r: r.variant[7:], ref=base)
    bar(s[s.variant.str.startswith("O4-")], "O4: software prefetch distance", "o4_prefetch.pdf", outdir,
        label=lambda r: r.variant[3:], ref=base)
    bar(s[s.variant.str.startswith(("O5-", "AB-"))], "Relabelling and alpha/beta", "o5_relabel_ab.pdf", outdir,
        label=lambda r: r.variant, ref=base)
    bar(s[s.variant.str.startswith("big-")], "kron22 (4x larger graph)", "big_graph.pdf", outdir,
        label=lambda r: r.variant[4:], ref=ref_median(s, "big-base"))

def read_perf_csv(path):
    vals = {}
    if not os.path.exists(path):
        return vals
    for line in open(path):
        if not line.strip() or line.startswith("#"):
            continue
        f = line.rstrip("\n").split(",")
        if len(f) < 3:
            continue
        try:
            vals[f[2]] = float(f[0])
        except ValueError:
            vals[f[2]] = float("nan")
    return vals

def counters(mdir, edges):
    files = glob.glob(os.path.join(mdir, "perf", "*__g*__n*.csv"))
    by = defaultdict(dict)
    ntr = None
    for f in files:
        m = re.match(r"(.+)__g(\d+)__n(\d+)\.csv", os.path.basename(f))
        v, g, n = m.group(1), m.group(2), int(m.group(3))
        if n:
            ntr = n
        for ev, val in read_perf_csv(f).items():
            by[(v, ev)][n] = val
    rows = []
    for (v, ev), d in sorted(by.items()):
        n0 = d.get(0, float("nan"))
        nN = [d[k] for k in d if k][0] if any(d) else float("nan")
        delta = nN - n0
        rows.append(dict(variant=v, event=ev, n0=n0, nN=nN, delta=delta,
                         per_trial=delta / ntr if ntr else float("nan"),
                         per_edge=delta / (ntr * edges) if ntr and edges else float("nan")))
    c = pd.DataFrame(rows)
    if c.empty:
        return c
    extra = []
    for v, g in c.groupby("variant"):
        e = dict(zip(g.event, g.delta))
        for pmu in ["", "cpu_core/", "cpu_atom/"]:
            def get(name):
                return e.get(f"{pmu}{name}/" if pmu else name, e.get(f"{pmu}{name}", float("nan")))
            cyc, ins = get("cycles"), get("instructions")
            if not np.isnan(cyc) and cyc > 0:
                extra.append(dict(variant=v, event=f"{pmu or 'all/'}IPC", delta=ins / cyc))
            for miss, ref in [("cache-misses", "cache-references"), ("LLC-load-misses", "LLC-loads"),
                              ("dTLB-load-misses", "dTLB-loads"), ("L1-dcache-load-misses", "L1-dcache-loads"),
                              ("branch-misses", "branches")]:
                a, b = get(miss), get(ref)
                if not np.isnan(a) and b and not np.isnan(b):
                    extra.append(dict(variant=v, event=f"{pmu or 'all/'}{miss} ratio", delta=a / b))
    return pd.concat([c, pd.DataFrame(extra)], ignore_index=True)

def papi_regions(mdir):
    rows = []
    for d in sorted(glob.glob(os.path.join(mdir, "papi", "papi_*"))):
        tot = defaultdict(lambda: defaultdict(float))

        def walk(o):
            if isinstance(o, dict):
                if "name" in o and isinstance(o["name"], str):
                    for k, val in o.items():
                        if k in ("name", "parent_region_id", "region_count"):
                            continue
                        try:
                            tot[o["name"]][k] += float(val)
                        except (TypeError, ValueError):
                            pass
                for val in o.values():
                    walk(val)
            elif isinstance(o, list):
                for val in o:
                    walk(val)
        for jf in glob.glob(os.path.join(d, "**", "*.json"), recursive=True):
            try:
                walk(json.load(open(jf)))
            except Exception as ex:
                print("  papi parse:", jf, ex)
        for region, evs in tot.items():
            for ev, val in evs.items():
                rows.append(dict(run=os.path.basename(d), region=region, event=ev, value=val))
    return pd.DataFrame(rows)

def key_numbers(mdir, s, c, outdir):
    lines = [f"# Key numbers: {os.path.basename(mdir)}", "",
             f"Warm-up trials dropped per process: {WARM}", ""]
    base = s[s.variant == "base"]
    if not base.empty:
        lines += ["## Baseline (kron20)", "", "| core set | threads | median ms | IQR ms | GTEPS |", "|---|---|---|---|---|"]
        for r in base.itertuples():
            lines.append(f"| {r.coreset} | {r.threads} | {r.median_ms:.2f} | {r.iqr_ms:.2f} | {r.gteps:.2f} |")
        lines.append("")
    for name in ["stream_all", "stream_P", "stream_E", "stream_1T"]:
        f = os.path.join(mdir, name + ".txt")
        if os.path.exists(f):
            vals = {l.split(":")[0]: float(l.split()[1]) for l in open(f) if re.match(r"^(Copy|Scale|Add|Triad):", l)}
            lines.append(f"STREAM {name[7:]}: " + ", ".join(f"{k} {v/1000:.1f} GB/s" for k, v in vals.items()))
    f = os.path.join(mdir, "latency.csv")
    if os.path.exists(f):
        lat = pd.read_csv(f)
        lines += ["", "## Load latency (pointer chase, ns)", ""]
        for core, g in lat.groupby("core"):
            lines.append(f"{core}-core: " + ", ".join(f"{int(r.size_kb)}KB {r.ns_per_load:.1f}" for r in g.itertuples()))
        fig, ax = plt.subplots()
        for core, g in lat.groupby("core"):
            ax.plot(g.size_kb, g.ns_per_load, "o-", label=f"{core}-core")
        ax.set_xscale("log", base=2)
        ax.set_xlabel("working set (KB)")
        ax.set_ylabel("ns per dependent load")
        ax.set_title("Memory hierarchy latency")
        ax.legend()
        fig.savefig(os.path.join(outdir, "latency.pdf"))
        plt.close(fig)
    for f in ["timer_resolution.txt", "sched_correctness.txt", "thp_usage.txt", "verify.txt"]:
        p = os.path.join(mdir, f)
        if os.path.exists(p):
            lines += ["", f"## {f}", "```", open(p).read().strip(), "```"]
    tg = sorted(glob.glob(os.path.join(mdir, "timers_gapbs_*.txt")))
    if tg:
        lines += ["", "## Timer cross-check (one process, NTR trials)", "",
                  "| rep | GAPBS read+trials s | perf duration_time s | perf task-clock s | /usr/bin/time elapsed s |", "|---|---|---|---|---|"]
        for i, f in enumerate(tg, 1):
            txt = open(f).read()
            trials = sum(float(x) for x in re.findall(r"Trial Time:\s+([\d.]+)", txt))
            read = sum(float(x) for x in re.findall(r"Read Time:\s+([\d.]+)", txt))
            pv = read_perf_csv(os.path.join(mdir, f"timers_perf_{i}.csv"))
            tf = os.path.join(mdir, f"timers_time_{i}.txt")
            tt = open(tf).read().split() if os.path.exists(tf) else []
            lines.append(f"| {i} | {read+trials:.3f} | {pv.get('duration_time', float('nan'))/1e9:.3f} | "
                         f"{pv.get('task-clock', float('nan'))/1e9:.3f} | {tt[0] if tt else 'n/a'} |")
    if c is not None and not c.empty:
        sel = c[c.variant.isin(["base-all", "base-P", "base-E", "base-1T"])]
        lines += ["", "## Counters (BFS only = n trials minus graph load)", "",
                  "| variant | event | per trial | per edge |", "|---|---|---|---|"]
        for r in sel.itertuples():
            if "ratio" in r.event or "IPC" in r.event:
                lines.append(f"| {r.variant} | {r.event} | {r.delta:.3f} | |")
            else:
                lines.append(f"| {r.variant} | {r.event} | {r.per_trial:.4g} | {r.per_edge:.4g} |")
    open(os.path.join(mdir, "key_numbers.md"), "w").write("\n".join(lines) + "\n")

def main():
    dirs = sys.argv[1:] or sorted(d for d in glob.glob(os.path.join(ROOT, "pe", "results", "*")) if os.path.isdir(d))
    for mdir in dirs:
        csvf = os.path.join(mdir, "timings.csv")
        if not os.path.exists(csvf):
            continue
        name = os.path.basename(mdir.rstrip("/"))
        outdir = os.path.join(ROOT, "pe", "plots", name)
        os.makedirs(outdir, exist_ok=True)
        tim = pd.read_csv(csvf, dtype={"schedule": str})
        s = summarize(tim)
        s.to_csv(os.path.join(mdir, "summary.csv"), index=False)
        cols = ["variant", "coreset", "threads", "schedule", "n", "median_ms", "iqr_ms", "gteps"]
        with open(os.path.join(mdir, "summary.md"), "w") as f:
            f.write("| " + " | ".join(cols) + " |\n|" + "---|" * len(cols) + "\n")
            for r in s[cols].itertuples(index=False):
                f.write("| " + " | ".join(f"{v:.3f}" if isinstance(v, float) else str(v) for v in r) + " |\n")
        plots_timings(tim, s, outdir)
        edges = float(s[s.variant == "base"].edges.iloc[0]) if (s.variant == "base").any() else float("nan")
        c = counters(mdir, edges)
        if not c.empty:
            c.to_csv(os.path.join(mdir, "counters.csv"), index=False)
        p = papi_regions(mdir)
        if not p.empty:
            p.to_csv(os.path.join(mdir, "papi_regions.csv"), index=False)
        key_numbers(mdir, s, c, outdir)
        print(f"{name}: {len(s)} configurations, {len(c)} counter rows, {len(p)} PAPI rows -> {outdir}")

if __name__ == "__main__":
    main()
