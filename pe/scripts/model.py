#!/usr/bin/env python3
import os
import re
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RES = os.path.join(ROOT, "pe", "results")
MLP_DEFAULT = 10.0

def edge_counts(graph="kron20", binary="bfs_count"):
    txt = open(os.path.join(RES, "common", "edge_counts.txt")).read()
    sec = re.search(rf"## {graph} {binary}\n(.*?)(?=\n## |\Z)", txt, re.S).group(1)
    n = int(re.search(r"Graph has (\d+) nodes", sec).group(1))
    m = int(re.search(r"nodes and (\d+) undirected", sec).group(1))
    ec = [tuple(map(int, x)) for x in re.findall(r"td_edges (\d+) bu_edges (\d+) bu_vertices (\d+)", sec)]
    trials = len(ec)
    steps = {k: len(re.findall(rf"^\s+{k}\s", sec, re.M)) / trials for k in ("td", "bu", "e", "c")}
    td, bu_e, bu_v = (np.mean([e[i] for e in ec]) for i in range(3))
    return dict(n=n, m=m, trials=trials, td_edges=td, bu_edges=bu_e, bu_vertices=bu_v, **steps)

def traffic(c):
    n = c["n"]
    parts = {
        "InitParent": 12 * n,
        "BU sweeps": c["bu"] * (12 * n + n / 8),
        "BU neighbour lines": 64 * c["bu_vertices"],
        "TD edges + parent[v]": 68 * c["td_edges"],
        "conversions": 2 * n / 8,
        "final pass": 8 * n,
    }
    return parts, sum(parts.values()), c["bu_vertices"] + c["td_edges"]

def stream_triad(mdir, tag):
    f = os.path.join(mdir, f"stream_{tag}.txt")
    if not os.path.exists(f):
        return float("nan")
    for line in open(f):
        if line.startswith("Triad:"):
            return float(line.split()[1]) * 1e6
    return float("nan")

def machine_params(mdir):
    lat = pd.read_csv(os.path.join(mdir, "latency.csv"))
    lat = lat[lat.core == lat.core.iloc[0]]
    l_dram = float(lat[lat.size_kb == lat.size_kb.max()].ns_per_load.iloc[0]) * 1e-9
    mlp, mlp_src = MLP_DEFAULT, "assumed"
    f = os.path.join(mdir, "mlp.csv")
    if os.path.exists(f):
        d = pd.read_csv(f)
        mlp = float(d[d.chains == 1].ns_per_load.iloc[0] / d.ns_per_load.min())
        mlp_src = "measured"
    return dict(B1=stream_triad(mdir, "1T"), Ball=stream_triad(mdir, "all"),
                L=l_dram, MLP=mlp, mlp_src=mlp_src)

def main():
    machines = sys.argv[1:] or ["wsl", "habrok"]
    c = edge_counts()
    parts, bytes_, nrand = traffic(c)
    out = ["# Performance model (kron20)", "",
           f"Graph: n = {c['n']:,}, undirected edges = {c['m']:,}, {c['trials']} trials counted.",
           f"Per trial: {c['td']:.2f} TD steps, {c['bu']:.2f} BU steps; edges examined "
           f"TD {c['td_edges']:,.0f} + BU {c['bu_edges']:,.0f} = "
           f"{(c['td_edges'] + c['bu_edges']) / (2 * c['m']) * 100:.1f}% of directed edges; "
           f"BU vertices checked {c['bu_vertices']:,.0f}.", "",
           "| traffic component | MB per trial |", "|---|---|"]
    out += [f"| {k} | {v / 1e6:.1f} |" for k, v in parts.items()]
    out += [f"| **total** | **{bytes_ / 1e6:.1f}** |", "",
            f"Random line accesses per trial N_rand = {nrand:,.0f}", ""]
    out += ["| machine | B_1T GB/s | B_all GB/s | L_dram ns | MLP | p | T_bw ms | T_lat ms | "
            "T_model ms | measured ms | measured / model |", "|---|---|---|---|---|---|---|---|---|---|---|"]
    os.makedirs(os.path.join(ROOT, "pe", "plots", "model"), exist_ok=True)
    fig, axes = plt.subplots(1, len(machines), figsize=(6.4 * len(machines) / 1.4, 3.6), squeeze=False)
    for ax, mname in zip(axes[0], machines):
        mdir = os.path.join(RES, mname)
        mp = machine_params(mdir)
        s = pd.read_csv(os.path.join(mdir, "summary.csv"))
        sc = s[s.variant == "scaling-bound"].sort_values("threads")
        p = sc.threads.values.astype(float)
        t_bw = bytes_ / np.minimum(p * mp["B1"], mp["Ball"]) * 1e3
        t_lat = nrand * mp["L"] / (mp["MLP"] * p) * 1e3
        t_mod = np.maximum(t_bw, t_lat)
        for i in sorted({0, int(np.argmin(sc.median_ms.values)), len(p) - 1}):
            out.append(f"| {mname} | {mp['B1']/1e9:.1f} | {mp['Ball']/1e9:.1f} | {mp['L']*1e9:.0f} | "
                       f"{mp['MLP']:.1f} ({mp['mlp_src']}) | {int(p[i])} | {t_bw[i]:.2f} | {t_lat[i]:.2f} | "
                       f"{t_mod[i]:.2f} | {sc.median_ms.values[i]:.2f} | {sc.median_ms.values[i] / t_mod[i]:.2f} |")
        ax.loglog(p, sc.median_ms, "o-", color="#1f77b4", label="measured (bound threads)")
        ax.loglog(p, t_bw, "--", color="#d62728", label="bandwidth bound")
        ax.loglog(p, t_lat, ":", color="#2ca02c", label=f"latency bound (MLP {mp['MLP']:.0f})")
        ax.set_title({"wsl": "Laptop (i7-12650H, WSL2)", "habrok": "Hábrók (2× EPYC 7763)"}.get(mname, mname))
        ax.set_xlabel("threads")
        ax.set_ylabel("ms per trial")
        ax.legend(fontsize=7)
    fig.tight_layout()
    fig.savefig(os.path.join(ROOT, "pe", "plots", "model", "model_vs_measured.pdf"), bbox_inches="tight")
    open(os.path.join(RES, "common", "model.md"), "w").write("\n".join(out) + "\n")
    print("\n".join(out))

if __name__ == "__main__":
    main()
