# Source Code

MATLAB implementation of the two-layer (PSO + Fuzzy Logic) coordinated EV
charging strategy and the backward/forward sweep load flow it is built on.

---

## How to run

From this `src/` folder, in MATLAB:

```matlab
>> startup                 % 1. add src/ and data/ to the MATLAB path
>> Uncoordinated_24Hrs     % 2. baseline scenario  (RUN THIS FIRST)
>> Coordinated_24Hrs       % 3. proposed strategy + comparison figures
```

**Order matters.** `Uncoordinated_24Hrs` leaves the baseline results
(`Voltage_all_unCo`, `Trans_Load_unCo`, `VSI_min_unCo`, …) in the workspace, and
`Coordinated_24Hrs` reuses them for its side-by-side comparison plots. Running
`Coordinated_24Hrs` on its own will error at the comparison-plot section.

> **Runtime note:** the optimizer evaluates a full load flow for every particle
> at every iteration (20 particles × 40 iterations ≈ 800 load-flow solutions per
> interval, over 96 intervals), so the coordinated run takes noticeably longer
> than the baseline.

**Requires:** MATLAB R2023a+ and the **Fuzzy Logic Toolbox**
(`mamfis`, `addMF`, `addRule`, `evalfis`).

---

## Files you run

| File | Role |
|---|---|
| `startup.m` | Path setup. Adds `src/` and `../data/` to the MATLAB path. Run once at the start of a session. |
| `Uncoordinated_24Hrs.m` | Baseline scenario — every present EV charges at full power on arrival until its target is met. Produces the reference results. Run first. |
| `Coordinated_24Hrs.m` | Main scenario — builds the fuzzy system and runs the PSO + Fuzzy controller over the 96 intervals, then generates the coordinated results and the comparison figures. |

## Files you do *not* run directly

These are functions called internally by the scripts above — they are not meant
to be executed on their own.

| File | Role |
|---|---|
| `run_PSO.m` | **Upper layer.** Particle swarm optimizer; returns the optimal active-charger vector `N_opt` (one value per aggregation) for an interval. |
| `evaluate_cost.m` | PSO fitness function. Runs a load flow for a candidate charger vector and returns the weighted cost (voltage violation, voltage fluctuation, energy backlog, transformer overload). |
| `fuzzy_EV_priority.m` | **Lower layer.** Mamdani fuzzy selector; scores the available EVs at an aggregation by energy demand, remaining time, and fairness, and returns the highest-priority ones to charge. |
| `Loadflow_33bus_PV_EV.m` | Backward/forward sweep load flow for the IEEE 33-bus feeder with PV and EV injections. Returns bus voltages, transformer loading, feeder current, and losses. Called many times per interval by the optimizer, and once for the final dispatch. |

---

## Two-layer control (summary)

Every 15-minute interval:

1. **PSO (upper layer)** decides *how many* chargers each aggregation may
   operate, scoring candidates on the actual network state via the embedded
   load flow.
2. **Fuzzy logic (lower layer)** decides *which* individual EVs receive those
   chargers, prioritizing by energy demand, remaining time, and fairness.

See `../docs/PROJECT_SUMMARY.md` for the full model, cost function, and workflow.
