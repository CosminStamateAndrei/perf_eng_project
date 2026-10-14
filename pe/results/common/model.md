# Performance model (kron20)

Graph: n = 1,048,576, undirected edges = 15,699,691, 16 trials counted.
Per trial: 4.25 TD steps, 2.50 BU steps; edges examined TD 286,935 + BU 1,202,922 = 4.7% of directed edges; BU vertices checked 1,659,885.

| traffic component | MB per trial |
|---|---|
| InitParent | 12.6 |
| BU sweeps | 31.8 |
| BU neighbour lines | 106.2 |
| TD edges + parent[v] | 19.5 |
| conversions | 0.3 |
| final pass | 8.4 |
| **total** | **178.8** |

Random line accesses per trial N_rand = 1,946,820

| machine | B_1T GB/s | B_all GB/s | L_dram ns | MLP | p | T_bw ms | T_lat ms | T_model ms | measured ms | measured / model |
|---|---|---|---|---|---|---|---|---|---|---|
| wsl | 12.3 | 15.9 | 376 | 15.7 (measured) | 1 | 14.59 | 46.74 | 46.74 | 56.51 | 1.21 |
| wsl | 12.3 | 15.9 | 376 | 15.7 (measured) | 8 | 11.26 | 5.84 | 11.26 | 8.39 | 0.74 |
| wsl | 12.3 | 15.9 | 376 | 15.7 (measured) | 10 | 11.26 | 4.67 | 11.26 | 9.54 | 0.85 |
| habrok | 34.7 | 327.0 | 99 | 21.7 (measured) | 1 | 5.15 | 8.86 | 8.86 | 24.89 | 2.81 |
| habrok | 34.7 | 327.0 | 99 | 21.7 (measured) | 48 | 0.55 | 0.18 | 0.55 | 1.38 | 2.52 |
| habrok | 34.7 | 327.0 | 99 | 21.7 (measured) | 128 | 0.55 | 0.07 | 0.55 | 3.53 | 6.46 |
