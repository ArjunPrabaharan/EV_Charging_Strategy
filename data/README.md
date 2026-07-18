# Data

Input files for the simulation: the EV charging profiles, the daily load/PV
scaling profiles, and the IEEE 33-bus network data.

The scripts in `src/` read these by bare filename (e.g.
`readtable('EV_Data_1.xlsx')`, `load('linedata33bus.m')`), so this folder must
be on the MATLAB path. Running `startup` from `src/` adds it automatically.

---

## EV charging profiles — `EV_Data_1.xlsx` … `EV_Data_5.xlsx`

One spreadsheet per EV aggregation (five aggregations). Each **row is one
vehicle**, with the following columns:

| Column | Meaning |
|---|---|
| `arr_int` | arrival interval index (1–96, one per 15 min) |
| `dep_int` | departure interval index (1–96) |
| `arr_SOC` | state of charge on arrival (%) |
| `exp_SOC` | target (expected) state of charge at departure (%) |
| `bat_cap` | battery capacity (kWh) |
| `energy_kWh` | grid-side energy required to reach the target SOC (kWh) |

The arrival/departure spread and energy demands are stochastic, giving a
realistic, time-varying charging population at each aggregation.

---

## Load and PV profiles — `Expected Scaling Factor for PV and Load.xlsx`

96 rows (one per 15-minute interval), giving the normalized daily profiles used
to scale the base loads and the PV generation:

| Column | Meaning |
|---|---|
| `Domestic_pu` | per-unit domestic load multiplier over the day |
| `PV_pu` | per-unit PV generation multiplier over the day (includes cloud-intermittency noise) |

---

## IEEE 33-bus network data

Plain ASCII matrices for the benchmark feeder, read with `load(...)`.

**`linedata33bus.m`** — one row per branch:

| Column | Meaning |
|---|---|
| 1 | branch number |
| 2 | from bus |
| 3 | to bus |
| 4 | resistance R (Ω) |
| 5 | reactance X (Ω) |

**`loaddata33bus.m`** — one row per bus:

| Column | Meaning |
|---|---|
| 1 | bus number |
| 2 | active power P (kW) |
| 3 | reactive power Q (kVAr) |

The base loads in `loaddata33bus.m` are scaled by the weak-grid factor
(κ = 2.1) inside the simulation, not in this file.
