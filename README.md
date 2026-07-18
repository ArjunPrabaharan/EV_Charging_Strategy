# Intelligent Coordinated EV Charging Strategy for Voltage and Thermal Stability in Weak Distribution Networks with High PV Penetration

MATLAB implementation of a **two-layer (PSO + Fuzzy Logic) coordinated EV charging strategy** for a weak 11 kV distribution network with high photovoltaic (PV) penetration.

---

## Overview

Rooftop PV and electric vehicles (EVs) stress a weak distribution feeder in opposite halves of the day: PV causes reverse power flow and voltage fluctuation around midday, while EV charging clusters in the evening peak and drives undervoltage and thermal overloading.

This project coordinates EV charging so the network stays inside its voltage and thermal limits while still serving almost all charging demand. The controller has two layers, run every 15 minutes:

| Layer | Method | Decides |
|---|---|---|
| Upper | Particle Swarm Optimization (PSO) | **How many** chargers each aggregation may operate (`N_opt`) |
| Lower | Mamdani Fuzzy Logic | **Which** individual EVs get those chargers |

The PSO objective embeds a backward/forward sweep load flow, so every candidate decision is scored on the *actual* network state (voltage, fluctuation, thermal loading, energy backlog).

### Key results (uncoordinated vs. coordinated)

| Metric | Uncoordinated | Coordinated | Change |
|---|---|---|---|
| Min. voltage, bus 18 (p.u.) | 0.92 | 0.94 | within limit |
| Transformer peak (MVA) | 11.3 | 10.0 | 1.3 shaved |
| Night-peak feeder avg. load (%) | 100.03 | 92.32 | −7.71 |
| Energy satisfaction (%) | 100 | 98.2 | −1.8 |
| Network losses (kWh) | 2,659.73 | 2,351.54 | −11.6% |
| Charging cost (LKR) | 414,108.75 | 365,854.50 | −11.7% |

---

## Test system

- Modified **IEEE 33-bus** radial distribution network, **11 kV**, 100 MVA base
- **10 MVA** distribution transformer; main-feeder ampacity **525 A**
- Weak-grid condition: base loads scaled by **κ = 2.1** → ≈ 9.18 MVA at 0.85 p.f.
- **5 PV sites** — 1000 kW each (5 MWp, ≈ 50% penetration)
- **5 EV aggregations** at buses 6, 14, 20, 23, 26 — up to 40 × 11 kW chargers each (200 EVs)
- Horizon: **96 × 15-minute intervals** (24 h); charging efficiency η_ch = 0.9
- Voltage limits: **0.94 – 1.06 p.u.**

---

## Repository structure

```
.
├── src/                       # main simulation code (run from here)
│   ├── startup.m                  # adds src/ and data/ to the MATLAB path — run first
│   ├── Coordinated_24Hrs.m        # main: PSO + Fuzzy coordinated simulation
│   ├── Uncoordinated_24Hrs.m      # baseline: greedy charge-on-arrival
│   ├── run_PSO.m                  # upper layer: particle swarm optimizer
│   ├── evaluate_cost.m            # PSO fitness (embeds the load flow)
│   ├── fuzzy_EV_priority.m        # lower layer: fuzzy priority + EV selection
│   └── Loadflow_33bus_PV_EV.m     # backward/forward sweep load flow (PV + EV)
├── data/                      # EV profiles, load/PV profiles, IEEE 33-bus network data
├── supplementary/             # preliminary scripts used to build/verify the model
├── docs/                      # project report + technical summary
└── Visualization Dashboard/   # interactive HTML dashboard of the results
```

Each folder has its own `README.md` with details on the files inside it.

---

## Requirements

- **MATLAB R2023a** (or later)
- **Fuzzy Logic Toolbox** — required for `mamfis`, `addMF`, `addRule`, `evalfis`

No other toolboxes are needed. The load flow and PSO are custom implementations.

---

## How to run

Execution order is **mandatory** — the coordinated script reuses the baseline results for its comparison plots.

```matlab
>> cd src
>> startup                 % add src/ and data/ to the path
>> Uncoordinated_24Hrs     % 1) baseline — produces Voltage_all_unCo, Trans_Load_unCo, VSI_min_unCo
>> Coordinated_24Hrs       % 2) proposed strategy + comparison figures
```

Running `Coordinated_24Hrs` on its own will error at the comparison-plot section, because the uncoordinated workspace variables will not exist.

> **Runtime note:** the PSO evaluates a full load flow for every particle at every iteration (20 particles × 40 iterations ≈ **800 load-flow solutions per interval**, × 96 intervals). Expect the coordinated run to take noticeably longer than the baseline.

---

## Input data

Full column definitions for the EV profiles, the load/PV scaling profiles, and the IEEE 33-bus line and load data are documented in [`data/README.md`](data/README.md).

---

## Supplementary code

`supplementary/` holds the preliminary scripts used to generate the inputs and validate the network model before the coordinated strategy was built. See [`supplementary/README.md`](supplementary/README.md) for details.

---

## Visualization dashboard

`Visualization Dashboard/` is an interactive, offline dashboard that presents every figure and the coordinated-vs-uncoordinated comparison in one place. Open `Visualization Dashboard/index.html` in a browser, or serve the folder locally — see [`Visualization Dashboard/README.md`](Visualization%20Dashboard/README.md).

---

## Documentation

- `docs/Project Report.pdf` — full project report
- `docs/PROJECT_SUMMARY.md` — condensed technical summary (model, algorithms, workflow)

---

## Citation

If you use this work, please cite the associated conference paper:

> *Intelligent Coordinated EV Charging Strategy for Voltage and Thermal Stability in Weak Distribution Networks with High PV Penetration.*

*(Paper under review)*
