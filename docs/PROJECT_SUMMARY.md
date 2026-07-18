# Project Summary

**Intelligent Coordinated EV Charging Strategy for Voltage and Thermal Stability in Weak Distribution Networks with High PV Penetration**

Implemented entirely in MATLAB.

---

## 1. What the project is

This project develops and simulates an **intelligent two-layer control strategy** for managing electric-vehicle (EV) charging across a weak electricity distribution network that also hosts a high level of rooftop/solar photovoltaic (PV) generation. The controller coordinates *when* and *how many* EVs charge so that the grid stays within its voltage and thermal limits, while still delivering the energy each EV needs before it departs.

The work is evaluated by comparing two scenarios over a full 24-hour day:

- **Uncoordinated charging** (baseline): every EV begins charging the moment it plugs in and continues until full. This is the "do nothing" case.
- **Coordinated charging** (proposed): a PSO + Fuzzy Logic controller decides charger activation and EV priority every 15 minutes.

---

## 2. The engineering problem

Mass EV adoption and rooftop solar both stress distribution networks that were never designed for them:

- **EV charging** adds large, clustered evening loads. When many vehicles charge simultaneously (typically after people return home), the network experiences **undervoltage** and **transformer/feeder thermal overload**.
- **PV generation** injects power during the day. On a weak grid this causes **overvoltage** and, because of passing clouds, **rapid voltage fluctuation** (flicker).

The two phenomena peak at different times but together push the grid outside the acceptable voltage band (0.94–1.06 pu) and beyond equipment thermal ratings. The engineering problem is to **absorb both the PV variability and the EV demand without violating voltage or thermal limits**, and without expensive network reinforcement.

---

## 3. Why coordinated charging is required

In the uncoordinated case, charging demand is synchronised by human behaviour — everyone plugs in at the evening peak, which coincides with the domestic load peak. The result is a deep voltage sag at the network extremities and a transformer loading that exceeds its 10 MVA rating.

Coordinated charging breaks this synchronisation. By **staggering and prioritising** charging across the day, the controller:

- shifts flexible load away from the critical evening peak,
- keeps all bus voltages inside limits,
- holds transformer and feeder loading under their thermal ratings,
- damps PV-induced voltage fluctuation, and
- still meets each EV's energy requirement before departure.

The same vehicles receive (almost) the same energy — but distributed intelligently in time.

---

## 4. The weak distribution grid model

A **"weak" grid** is one with high source impedance relative to its load, so voltage is highly sensitive to power flow. In this model the weakness is created deliberately by **scaling the standard domestic loads by 2.1×**. This pushes the network close to its limits, making the impact of EV and PV clearly visible and giving the controller a meaningful job to do.

### IEEE 33-bus system

The network is the **modified IEEE 33-bus radial distribution feeder**, a standard benchmark:

- 33 buses, radial topology, fed from a single substation (slack bus).
- Operating voltage **11 kV**, **100 MVA** system base, **10 MVA** distribution transformer.
- Main feeder ampacity limit **525 A**.
- Bus voltages must remain within **0.94–1.06 pu**.

Onto this base network the project adds 5 PV sites and 5 EV charging aggregations (see below).

### Domestic load modelling

Each bus carries its standard IEEE 33-bus active/reactive load, scaled by 2.1× (the weak-grid factor) and further modulated through the day by a **per-unit domestic demand profile** (`Domestic_pu`, 96 values, one per 15-min interval). This produces a realistic daily load curve with morning and evening peaks.

### PV modelling

**5 PV sites** (buses 10, 17, 22, 25, 32), each rated **1000 kW** → 5 MW total installed. Generation follows a **per-unit solar profile** (`PV_pu`, 96 values) that ramps up in the morning, peaks at midday, and falls in the evening. PV is treated as negative load: `S_net = S_load − S_pv`. The midday PV peak (roughly intervals 30–60) is the window where overvoltage and fluctuation are most likely.

### EV profile modelling

**5 EV aggregations** (buses 6, 14, 20, 23, 26), each representing a cluster of up to ~40 charging points at **11 kW** per charger. Each EV is described by a row in `EV_Data_1.xlsx … EV_Data_5.xlsx`:

| Field | Meaning |
|---|---|
| `arr_int`, `dep_int` | arrival / departure interval (1–96) |
| `arr_SOC`, `exp_SOC` | arrival and target state-of-charge (%) |
| `bat_cap` | battery capacity (kWh) |
| `energy_kWh` | energy required to reach the target SOC |

The arrival/departure spread and energy demands are stochastic, producing a realistic, time-varying charging population at each station.

### Backward-Forward Sweep load flow

Because the network is radial, voltages and currents are solved with the **Backward-Forward Sweep (BFS)** method rather than a full Newton-Raphson solver:

1. **Backward sweep** — starting from the leaf buses and working toward the substation, accumulate branch currents from downstream load currents.
2. **Forward sweep** — starting from the slack bus and working outward, update each bus voltage from its upstream voltage and the branch voltage drop.
3. Iterate until the maximum voltage mismatch falls below tolerance.

The solver returns the bus voltage profile (33×1, pu), bus apparent power, line losses, and line currents — including the transformer loading and main-feeder current used to check thermal limits. It is called once per interval for the final dispatch, and many times internally by the optimiser.

---

## 5. The two-layer control architecture

The controller is **hierarchical**, separating the *grid-level* decision from the *vehicle-level* decision:

```
        ┌──────────────────────────────────────────────┐
        │   UPPER LAYER  —  PSO (system optimiser)       │
        │   How many chargers to switch ON per station?  │
        │   Output: N_opt (1×5)                          │
        └───────────────────────┬──────────────────────┘
                                 │  N_opt(s) chargers for station s
        ┌───────────────────────▼──────────────────────┐
        │   LOWER LAYER  —  Fuzzy Logic (EV selector)    │
        │   WHICH individual EVs get those chargers?     │
        │   Output: selected EV indices per station      │
        └────────────────────────────────────────────────┘
```

Running every 15 minutes, the upper layer decides the *quantity* of charging at each location to respect grid constraints; the lower layer decides the *identity* of the vehicles to serve, based on fairness and urgency.

### Upper layer — PSO optimisation

A **Particle Swarm Optimisation** (`run_PSO.m`) searches for the best number of active chargers per station for the current interval.

- **Decision variable**: a 5-element vector — active chargers per station, each bounded by the number of EVs actually waiting at that station.
- **Swarm**: 20 particles, 40 iterations, inertia `w = 1` (damped ×0.95 each iteration), cognitive `c1 = 1.5`, social `c2 = 2.0`.
- **Fitness** (`evaluate_cost.m`): each candidate runs a load flow and is scored by a weighted multi-objective cost:
  - **J1 — Voltage violation**: penalty for any bus outside 0.94–1.06 pu (dominant weight, near-hard constraint).
  - **J2 — Voltage fluctuation**: penalty on bus-18 voltage deviating from the 3-interval rolling mean, active during the PV-peak window — this smooths solar-induced flicker.
  - **J3 — Energy backlog**: rewards serving demand (penalises leaving energy undelivered).
  - **J4 — Transformer overload**: quadratic penalty for transformer loading above 10 MVA (thermal stability).

The optimiser returns `N_opt`, the activation count per station that best balances voltage stability, thermal safety, and demand fulfilment.

### Lower layer — Fuzzy Logic allocation

Once the upper layer fixes *how many* chargers a station may use, the **Mamdani fuzzy system** (`fuzzy_EV_priority.m`) decides *which* waiting EVs receive them. Each available EV is scored on three inputs:

- **Energy Demand** — how much charge it still needs (normalised).
- **Remaining Time** — intervals left before its departure (urgency).
- **Fairness Index** — how long it has already waited (prevents starvation).

A 27-rule (3×3×3) Mamdani rulebook maps these to a single **Priority** score. The EVs are ranked, and the top `N_opt(s)` of them are charged this interval at full charger power. This guarantees that urgent, high-need, or long-waiting vehicles are prioritised while never exceeding the grid-safe charger count.

---

## 6. Simulation workflow

The day is simulated as **96 intervals of 15 minutes**. Each interval:

1. Process EV arrivals and departures; update who is present and how much energy each still needs.
2. Count available EVs per station and run **PSO** → `N_opt`.
3. Run the final **load flow** with `N_opt` to record voltages, transformer/feeder loading, losses, and the Voltage Stability Index (VSI).
4. Run the **fuzzy allocator** to choose which EVs charge, and decrement their remaining energy.
5. Store results for plotting.

Two scripts are executed in order:

1. **`Uncoordinated_24Hrs.m`** first — produces the baseline and stores comparison variables (voltage, transformer load, VSI) in the workspace.
2. **`Coordinated_24Hrs.m`** next — runs the PSO + Fuzzy controller and generates side-by-side comparison plots against the baseline.

---

## 7. Project folder contents

### MATLAB files

| File | Purpose |
|---|---|
| `Coordinated_24Hrs.m` | Main simulation — builds the fuzzy system, runs the PSO + Fuzzy controller over 96 intervals, and generates all coordinated results and comparison plots. |
| `Uncoordinated_24Hrs.m` | Baseline greedy simulation — every present EV charges immediately. Must run first; provides the comparison data. |
| `run_PSO.m` | Particle Swarm Optimisation; returns the optimal active-charger vector `N_opt` per interval. |
| `evaluate_cost.m` | PSO fitness function; runs a load flow and returns the weighted multi-objective cost (voltage, fluctuation, backlog, thermal). |
| `fuzzy_EV_priority.m` | Mamdani fuzzy selector; scores and ranks individual EVs and returns those chosen to charge. |
| `Loadflow_33bus_PV_EV.m` | Backward-Forward Sweep load flow for the 33-bus network with PV and EV injections. |
| `loaddata33bus.m`, `linedata33bus.m` | IEEE 33-bus bus-load and line-impedance data. |

### Data files

| File | Purpose |
|---|---|
| `EV_Data_1.xlsx … EV_Data_5.xlsx` | Per-EV charging profiles for the 5 aggregations (arrival, departure, SOC, capacity, energy demand). |
| `Expected Scaling Factor for PV and Load.xlsx` | 96-row daily per-unit profiles for domestic load (`Domestic_pu`) and PV (`PV_pu`). |

---

## 8. The dashboard

The **Visualization Dashboard** in this repository presents the exported figures, organised into numbered sections by scenario and result type (e.g. *Uncoordinated EV Charging → Voltage profile of 33 buses*, *EV charging schedules*, etc.). It is an interactive, offline walkthrough of the results — see `Visualization Dashboard/README.md`.

### Purpose and what it demonstrates

The dashboard is the **visual evidence base** of the project. It is intended to demonstrate, at a glance, that the coordinated strategy keeps the weak grid stable under high EV and PV penetration where the uncoordinated baseline fails. It tells the story by pairing the two scenarios across the same set of metrics.

### Results the dashboard should showcase

- **Bus voltage profiles** — bus 18 (a critical far-end bus) and all 33 buses over 24 hours, coordinated vs uncoordinated, against the 0.94 pu limit. Coordinated charging keeps voltage inside the band; the baseline sags below it at the evening peak.
- **Transformer loading** — apparent power vs the 10 MVA rating. The baseline overloads the transformer at peak; the coordinated case stays under the limit.
- **Main feeder current** — line current vs the 525 A ampacity during the night peak.
- **Voltage Stability Index (VSI)** — worst-case VSI per bus, coordinated vs uncoordinated, showing improved stability margins under coordination.
- **EV charging schedules** — colour-coded per-EV status grids (absent / charging / connected-but-waiting / fully charged) for each station, illustrating how the controller staggers charging while still completing every vehicle's demand.
- **Charging activity and demand satisfaction** — number of simultaneously charging EVs per station, energy requested vs delivered, average fleet SOC over time, and departure-SOC vs target-SOC scatter — confirming that coordination meets energy needs despite spreading the load.
- **Energy and cost summary** — total energy consumed, network losses, and time-of-use charging cost.

Together these figures show the central result: **coordinated PSO + Fuzzy charging delivers essentially the same EV energy as the uncoordinated baseline, but without the voltage violations and thermal overloads** — keeping a weak, high-PV distribution grid stable across the full day.
