# Supplementary Code

Preliminary MATLAB scripts used to **generate the simulation inputs** and to **build and verify the network model** before the two-layer coordinated strategy in `src/` was developed.

These are kept for transparency and reproducibility. They are **not** part of the main simulation pipeline — you do not need to run them to reproduce the results, since their outputs are already provided in `data/`.

---

## Profile modelling — `profile_modelling/`

Scripts that synthesize the daily profiles and the EV fleet.

| File | Purpose |
|---|---|
| `Load_Profile.m` | Generates the normalized domestic load profile. Built from a base load plus Gaussian morning, midday, and evening components, with small smoothed random fluctuations. Produces the `Domestic_pu` curve. |
| `PV_Profile.m` | Generates the normalized PV profile. Starts from an ideal bell-shaped irradiance curve (sunrise 06:00 → sunset 18:00), normalized to per unit, then adds random noise to reproduce **cloud-induced intermittency**. Produces the `PV_pu` curve. |
| `EV_Profile.m` | Synthetic EV dataset generator for a 40-vehicle, 11 kW charging station. Samples daytime and night-time arrival/departure times, arrival and target SOC, and battery capacity (from 40/50/60/80/90 kWh options) to build a realistic, heterogeneous fleet. Its output is the raw form of the per-aggregation `EV_Data_*.xlsx` files in `data/`. |

---

## Network model verification

Scripts used to build up and sanity-check the load flow and stability analysis.

| File | Purpose |
|---|---|
| `Loadflow_33bus_PV.m` | Earlier backward/forward sweep load flow with **PV only** (no EV load). The precursor to `src/Loadflow_33bus_PV_EV.m`. Returns bus voltages, load currents, bus power, and branch losses. |
| `Power_Flow_24Hrs.m` | Runs `Loadflow_33bus_PV` across all 96 intervals using the load/PV profiles, producing the 24-hour bus voltage matrix. Used to study the network **before** EV charging was introduced. |
| `VSI_PV_EV.m` | Standalone Voltage Stability Index calculation across the day, used to develop and verify the VSI formulation later embedded in the main simulation. |
| `EV_Occupancy.m` | Computes and plots aggregation **occupancy** over the day from `EV_Data_1.xlsx`, by accumulating arrivals and departures across the 96 intervals. Used to validate that the generated EV profiles produce a realistic occupancy curve. |

---

## Notes

- These scripts expect their input files (e.g. `EV_Data_1.xlsx`, `Expected Scaling Factor for PV and Load.xlsx`, `linedata33bus.m`) to be on the MATLAB path. Run `startup` from the `src/` folder first to add `src/` and `data/` to the path.
- `VSI_PV_EV.m` and `Power_Flow_24Hrs.m` reference column names (`Hour` / `Time`) from the profile spreadsheet; check the column name matches your copy if you re-run them.
- Because the profile generators use random noise / sampling, re-running them produces a **new** dataset. The datasets actually used for the published results are the ones committed in `data/`.
