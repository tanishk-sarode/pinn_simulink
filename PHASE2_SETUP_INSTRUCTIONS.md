# Phase 2 Setup Instructions — PINN vs Simulink

## Overview

Phase 2 uses the Simulink model as the high-fidelity reference for training PINNs,
replacing the RK4 solution used in Phase 1.

**Workflow:**
1. Fix the Simulink base model (one-time manual edit)
2. Run `matlab/run_scenarios.m` to simulate and export data
3. Run the PINN notebooks in `pinn_simulink/`

---

## Parameter Sources

All values used in this project come from **Anderson & Fouad, "Power System Control and
Stability"**, the IEEE 9-bus example (Example 2.6 / Example 2.7 in the textbook).
The source files in `textbook_question_details/` are the scanned pages used.

| Value | Source location | Where to verify |
|-------|----------------|-----------------|
| Generator MVA, kV, Speed | Table 2.1 (→ `table_2.1.jpeg`) | Column headers |
| Xd, Xd', Xq, Xq', Xl (system base) | Table 2.1 (→ `table_2.1.jpeg`) | Rows per generator |
| Stored energy H (MJ) | Table 2.1 last row (→ `table_2.1.jpeg`) | "Stored energy at rated speed" |
| E₁, E₂, E₃ and δ₀ values | Example 6.1 (→ `example_6_1.png`) | Listed as solution step 3 |
| Generator MW output (→ Pm) | Fig 2.19 load flow (→ `fig_2_19.png`) | MW values at each generator bus |
| Network impedances | Table 2.2 / Fig 2.18 (→ `example_6_2.png`, `fig_2_18.png`) | Line impedances and transformer reactances |
| Y_fault, Y_clear matrices | Derived from Table 2.4/2.5 (textbook); already used in `pinn_rk4/pinn-scenario-1-final.ipynb` | Cross-check with Phase 1 notebook values |

---

## Step 1 — Fix G1 in Simulink GUI (one-time, manual)

The G1 (247.5 MVA Hydro) block has placeholder reactances `[31, 32, 33, 34, 35, 36, 37]`
that need to be replaced with the correct values from **Table 2.1** (`table_2.1.jpeg`).

### Where the values come from

**Table 2.1** lists all reactances **on the 100 MVA system base**. We confirmed this is
system base (not machine base) because G2 and G3 in the current Simulink model already have
their values entered as `X_table × (MVA_machine / 100)`:

- G2 check: Xd_table = 0.8958 (Table 2.1) × (192/100) = **1.72** → matches current model ✓
- G2 check: Xd'_table = 0.1198 (Table 2.1) × (192/100) = **0.23** → matches current model ✓
- G3 check: Xd_table = 1.3125 (Table 2.1) × (128/100) = **1.68** → matches current model ✓

So the Simulink block stores values on **machine base** = `X_table × (MVA_machine / 100)`.
G1 must follow the same convention.

### How to calculate G1 Reactances (247.5 MVA, from `table_2.1.jpeg`)

Open `textbook_question_details/table_2.1.jpeg` and look at the **Gen 1 (Hydro)** column:

| Parameter | From Table 2.1 (system base, 100 MVA) | × (247.5 / 100) | = Simulink value (machine base) |
|-----------|---------------------------------------|-----------------|----------------------------------|
| Xd        | 0.1460                                | × 2.475         | **0.3614**                       |
| Xd'       | 0.0608                                | × 2.475         | **0.1505**                       |
| Xd''      | not in table — set equal to Xd'       | × 2.475         | **0.1505**                       |
| Xq        | 0.0969                                | × 2.475         | **0.2399**                       |
| Xq'       | 0.0969 (same as Xq for hydro)         | × 2.475         | **0.2399**                       |
| Xq''      | not in table — set equal to Xq'       | × 2.475         | **0.2399**                       |
| Xl        | 0.0336                                | × 2.475         | **0.0832**                       |

> Note: Xd'' and Xq'' (subtransient reactances) are not listed in Table 2.1. Setting them equal
> to the transient values (Xd', Xq') is the standard conservative approximation when subtransient
> data is unavailable.

### Editing steps

1. Open `matlab/IEEE_9bus_new_wow_mach_9.slx` in MATLAB/Simulink.

2. Double-click the block named **"247.5 MVA 16.5 kV 180 rpm"** (G1).

3. In the block dialog, change **Reactances1** to:
   ```
   [0.3614, 0.1505, 0.1505, 0.2399, 0.2399, 0.2399, 0.0832]
   ```
   Format: [Xd, Xd', Xd'', Xq, Xq', Xq'', Xl]

4. Keep all other G1 parameters unchanged — they are already correct:

   | Parameter | Current value | Why it's correct |
   |-----------|--------------|-----------------|
   | RotorType | Salient-pole | G1 is hydro → salient-pole ✓ |
   | PolePairs | 20 | 180 rpm at 60 Hz → 60×60/180 = 20 pole pairs ✓ |
   | Mechanical[0] (H) | 9.55 s | Table 2.1: stored energy = 2364 MJ / 247.5 MVA = 9.55 s (machine base) → 9.55 × 247.5/100 = 23.64 s (system base) ✓ |
   | NominalParameters | [247.5E6, 16500, 60] | Table 2.1: 247.5 MVA, 16.5 kV, 60 Hz ✓ |

   Same confirmation for G2 and G3 (already correct, no changes needed):

   | Generator | H (machine base) | H (system base) | Source |
   |-----------|-----------------|-----------------|--------|
   | G1 (247.5 MVA) | 9.55 s | 9.55 × 2.475 = **23.64 s** | Table 2.1: 2364 MJ / 247.5 MVA |
   | G2 (192 MVA)   | 3.33 s | 3.33 × 1.920 = **6.40 s**  | Table 2.1: 640 MJ / 192 MVA |
   | G3 (128 MVA)   | 2.35 s | 2.35 × 1.280 = **3.01 s**  | Table 2.1: 301 MJ / 128 MVA |

5. Click **OK**, then run **powergui → Tools → Load Flow → Compute → Apply to model**.

6. Verify the initial rotor angles match the values from **`example_6_1.png`**
   (listed as the internal voltage solution in Example 6.1 / Example 2.6):
   - G1 ≈ **2.2717°** (E₁ = 1.0566 ∠ 2.2717°)
   - G2 ≈ **19.7315°** (E₂ = 1.0502 ∠ 19.7315°)
   - G3 ≈ **13.1752°** (E₃ = 1.0170 ∠ 13.1752°)

7. **Save** `IEEE_9bus_new_wow_mach_9.slx`.

---

## Step 2 — Run Scenario 1 (Three-Phase Fault at Bus 7)

**Scenario source:** Example 2.6 / Example 2.7 in textbook (`example_6_1.png`, `example_6_2.png`).
Fault: three-phase fault near Bus 7 at the end of line 5-7, cleared in 5 cycles by opening line 5-7.

1. In MATLAB, navigate to the `matlab/` folder:
   ```matlab
   cd('path/to/pinn_simulink/matlab')
   ```

2. Open `run_scenarios.m` and confirm `scenario = 1` at the top.

3. Run the script:
   ```matlab
   run_scenarios
   ```

4. The script will:
   - Copy the base model to `scenario_1.slx`
   - Set StopTime = 2.0 s (same as Phase 1 RK4 notebooks)
   - Set fault SwitchTimes = `[1/600, 5/60]`
     - ON at 1/600 s ≈ 1.67 ms (near t=0, lets the model initialize)
     - OFF at 5/60 s ≈ 83.3 ms (5 cycles at 60 Hz — textbook fault clearing time)
   - Wire BusSelector outputs to To Workspace blocks
   - Run the simulation
   - Export delta (radians) and omega (rad/s) to `scenario_1_simulink_outputs.mat`
   - Save a quickcheck plot `scenario_1_simulink_quickcheck.png`

5. **IC check**: The script prints initial angle offsets vs RK4 reference.
   Acceptable threshold: < 1.0° per generator.
   If offset is large, repeat Step 1 (load flow may not have been re-run after fixing G1).

---

## Step 3 — Set Up Scenario 2 (50% Load Outage at Bus 8)

**Scenario source:** Defined for Phase 1 of this research project (not a textbook example).
Bus 8 load values (100 MW, 35 MVAR) are from **Fig 2.19** (`fig_2_19.png`) — "Load C at Bus 8".
50% outage = removing 50 MW / 17.5 MVAR by opening a breaker at 5/60 s.

### 3a. Generate the base scenario_2.slx

Set `scenario = 2` in `run_scenarios.m` and run it once.
This creates `scenario_2.slx` and disables the Three-Phase Fault block.
The simulation will likely fail — that is expected until the load split is done.

### 3b. Manual wiring in Simulink GUI

1. Open `scenario_2.slx`.

2. Find the **Bus 8 load block** (Three-Phase Parallel/Series RLC Load, 100 MW / 35 MVAR).
   It is usually labelled "Load C" or "Bus 8 Load".
   Source: **Fig 2.19** (`fig_2_19.png`) shows Bus 8 load = 100 MW, 35 MVAR.

3. **Split the load into two equal halves:**
   - Copy the load block (Ctrl+C, Ctrl+V).
   - Set each copy to **50 MW / 17.5 MVAR**.
   - Connect both halves in parallel to the same Bus 8 node.

4. **Add a Three-Phase Breaker in series with one half:**
   - Insert a Three-Phase Breaker between Bus 8 and one of the 50 MW load copies.
   - Breaker parameters:
     - Initial state: **closed** (load is connected at t=0)
     - Switching times: `[ct]` (opens at t = 5/60 s = 0.0833 s — same clearing time as Scenario 1)
     - Transition: open

5. **Save** `scenario_2.slx`.

### 3c. Run the Scenario 2 simulation

In `run_scenarios.m`, change to `scenario = 2` and run:
```matlab
run_scenarios
```

This produces `scenario_2_simulink_outputs.mat` and `scenario_2_simulink_quickcheck.png`.

---

## Step 4 — Upload .mat Files to Kaggle

The PINN notebooks are designed to run on Kaggle (GPU environment).

Upload the following files as a Kaggle dataset (e.g. named `simulink-outputs`):
- `matlab/scenario_1_simulink_outputs.mat`
- `matlab/scenario_2_simulink_outputs.mat`

Each file contains:
| Variable       | Shape    | Description                              |
|----------------|----------|------------------------------------------|
| T_ref          | (4001,)  | Time vector, 0 to 2.0 s, step = 5e-4 s  |
| delta_sim_i    | (4001,3) | Rotor angles in radians [G1, G2, G3]     |
| omega_sim_i    | (4001,3) | Angular velocity deviations in rad/s     |
| delta0_sim     | (1,3)    | Initial angles in radians (for PINN IC)  |
| omega0_sim     | (1,3)    | Initial omega in rad/s (for PINN IC)     |

---

## Step 5 — Run PINN Notebooks

The PINN uses **the same classical swing equations as Phase 1** as its physics loss:
- dδ/dt = ω
- dω/dt = (Pm − Pe) / M

The Simulink trajectory is only used as supervised data anchor — not as physics.
This tests whether a classical-physics PINN can fit a more realistic (full d-q) reference.

**Key physics parameters** (same as Phase 1, sourced as below):

| Parameter | Values [G1, G2, G3] | Source |
|-----------|--------------------|----|
| H (sys base) | [23.64, 6.40, 3.01] s | Computed from Table 2.1 stored energy / MVA (see Step 1) |
| E (internal voltage) | [1.0566, 1.0502, 1.0170] pu | `example_6_1.png` — Example 6.1 step 3 |
| δ₀ (initial angle) | [2.2717°, 19.7315°, 13.1752°] | `example_6_1.png` — same source |
| Pm (mech. power) | [0.716, 1.630, 0.850] pu | `fig_2_19.png` — G1=71.6 MW, G2=163 MW, G3=85 MW on 100 MVA base |
| D (damping) | [0, 0, 0] | Example 2.6 states "damping neglected" |
| Y_fault, Y_clear | See notebooks | Reduced Y matrices from textbook Tables 2.4/2.5; already verified in Phase 1 (`pinn_rk4/pinn-scenario-1-final.ipynb`) |

**Running the notebooks:**

1. On Kaggle, create a new notebook and attach the `simulink-outputs` dataset.

2. Update `MAT_PATH` in the notebook:
   ```python
   # Scenario 1
   MAT_PATH = '/kaggle/input/simulink-outputs/scenario_1_simulink_outputs.mat'

   # Scenario 2
   MAT_PATH = '/kaggle/input/simulink-outputs/scenario_2_simulink_outputs.mat'
   ```

3. Run `pinn_simulink/pinn-simulink-scenario-1.ipynb` for Scenario 1.

4. Run `pinn_simulink/pinn-simulink-scenario-2.ipynb` for Scenario 2.

5. Each notebook produces:
   - `results_detailed.csv` — full trajectory comparison table
   - `summary_statistics.txt` — error metrics
   - Plots: Simulink reference, PINN output, comparison, error analysis

---

## Verification Checklist

| Check | Expected | Where to confirm |
|-------|----------|-----------------|
| G1 Xd on system base | 0.1460 | `table_2.1.jpeg`, Gen 1 column, Xd row |
| G1 Xd on machine base | 0.1460 × (247.5/100) = 0.3614 | Computed |
| G1 H on machine base | 2364 / 247.5 = 9.55 s | `table_2.1.jpeg`, stored energy row |
| G1 H on system base | 9.55 × (247.5/100) = 23.64 s | Used in RK4 notebooks ✓ |
| G2 consistency check | 0.8958 × (192/100) = 1.72 → matches current G2 Xd in model | `old_system_params_simulink_file.txt` line 67 |
| G3 consistency check | 1.3125 × (128/100) = 1.68 → matches current G3 Xd in model | `old_system_params_simulink_file.txt` line 27 |
| Load flow initial angles | G1≈2.27°, G2≈19.73°, G3≈13.18° | `example_6_1.png` |
| IC offset in run_scenarios.m | < 1.0° per generator | Script output |
| Quickcheck plot (S1) | Oscillating angles, fault cleared at ~0.083 s | `scenario_1_simulink_quickcheck.png` |
| Bus 8 load value | 100 MW / 35 MVAR | `fig_2_19.png`, Bus 8 node |
| Fault clearing time | 5/60 ≈ 0.0833 s | `example_6_1.png` — "5 cycles" |

---

## File Reference

```
pinn_simulink/
├── textbook_question_details/        ← Source material
│   ├── table_2.1.jpeg                  Generator data (H, reactances)
│   ├── example_6_1.png                 E, delta0 values; fault description
│   ├── example_6_2.png                 Table 2.2 network data
│   ├── fig_2_18.png                    Impedance diagram
│   ├── fig_2_19.png                    Load flow diagram (generator MW, bus loads)
│   └── readme.md                       Problem summary
├── matlab/
│   ├── IEEE_9bus_new_wow_mach_9.slx   ← Base model (fix G1 Reactances1 here)
│   ├── run_scenarios.m                ← Main simulation script (NEW, use this)
│   ├── check_model_params.m           ← Diagnostic script (read-only)
│   ├── old_system_params_simulink_file.txt  ← Pre-fix model dump (for reference)
│   └── [old scripts — ignore]         setup_scenario_*.m, wire_workspace_blocks.m
├── pinn_rk4/
│   ├── pinn-scenario-1-final.ipynb    ← Phase 1 (RK4 reference) — complete
│   └── pinn-scenario-2-final.ipynb    ← Phase 1 (RK4 reference) — complete
└── pinn_simulink/
    ├── pinn-simulink-scenario-1.ipynb ← Phase 2 (Simulink reference) — NEW
    └── pinn-simulink-scenario-2.ipynb ← Phase 2 (Simulink reference) — NEW
```
