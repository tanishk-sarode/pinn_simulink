# Phase 2 Setup Instructions — PINN vs Simulink

## Overview

Phase 2 uses the Simulink model as the high-fidelity reference for training PINNs,
replacing the RK4 solution used in Phase 1.

**Workflow:**
1. Fix the Simulink base model (one-time manual edit)
2. Run `matlab/run_scenarios.m` to simulate and export data
3. Run the PINN notebooks in `pinn_simulink/`

---

## Step 1 — Fix G1 in Simulink GUI (one-time, manual)

The G1 (247.5 MVA Hydro) block has placeholder reactances `[31, 32, 33, 34, 35, 36, 37]`
that need to be replaced with the correct IEEE 9-bus values (Anderson & Fouad, Table 2.1,
converted from system base to machine base).

1. Open `matlab/IEEE_9bus_new_wow_mach_9.slx` in MATLAB/Simulink.

2. Double-click the block named **"247.5 MVA 16.5 kV 180 rpm"** (G1).

3. In the block dialog, change **Reactances1** to:
   ```
   [0.3614, 0.1505, 0.1505, 0.2399, 0.2399, 0.2399, 0.0832]
   ```
   (These are [Xd, Xd', Xd'', Xq, Xq', Xq'', Xl] on machine base, 247.5 MVA)

   Derivation for reference:
   | Parameter | Table 2.1 (sys base) | × (247.5/100) | = Machine base |
   |-----------|---------------------|---------------|----------------|
   | Xd        | 0.1460              |               | 0.3614         |
   | Xd'       | 0.0608              |               | 0.1505         |
   | Xd''      | ≈ Xd'               |               | 0.1505         |
   | Xq        | 0.0969              |               | 0.2399         |
   | Xq'       | 0.0969              |               | 0.2399         |
   | Xq''      | ≈ Xq'               |               | 0.2399         |
   | Xl        | 0.0336              |               | 0.0832         |

4. Keep all other G1 parameters unchanged:
   - RotorType = Salient-pole  ✓
   - PolePairs = 20            ✓  (hydro, 180 rpm at 60 Hz)
   - Mechanical = [9.55, 0, 20] ✓ (H = 9.55 s on machine base → 23.64 s on system base)
   - NominalParameters = [247.5E6, 16500, 60] ✓

5. Click **OK** to close the block dialog.

6. Open **powergui** → **Tools** → **Load Flow**.
   - Click **Compute** (or Run).
   - Accept the results (click **Apply to model**).
   - Verify the initial rotor angles in the results are approximately:
     - G1 ≈ 2.27°
     - G2 ≈ 19.73°
     - G3 ≈ 13.18°
   - If the angles are far off, check that Reactances1 was set correctly.

7. **Save** `IEEE_9bus_new_wow_mach_9.slx`.

> G2 and G3 are already correct and do not need changes.

---

## Step 2 — Run Scenario 1 (Three-Phase Fault at Bus 7)

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
   - Set StopTime = 2.0 s, fault SwitchTimes = [1/600, 5/60]
   - Wire BusSelector outputs to To Workspace blocks
   - Run the simulation
   - Export delta (radians) and omega (rad/s) to `scenario_1_simulink_outputs.mat`
   - Save a quickcheck plot `scenario_1_simulink_quickcheck.png`

5. **IC check**: The script prints initial angle offsets vs RK4 reference values.
   Acceptable threshold: < 1.0° per generator.
   If offset is large, repeat Step 1 (load flow may not have been re-run after fixing G1).

---

## Step 3 — Set Up Scenario 2 (50% Load Outage at Bus 8)

Scenario 2 requires a one-time manual Simulink edit to split the Bus 8 load.

### 3a. Generate the base scenario_2.slx

Run `run_scenarios.m` once with `scenario = 2`.
This creates `scenario_2.slx` and disables the Three-Phase Fault block.
The simulation will likely fail at this stage — that is expected.

### 3b. Manual wiring in Simulink GUI

1. Open `scenario_2.slx`.

2. Find the **Bus 8 load block** (Three-Phase Parallel/Series RLC Load, 100 MW / 35 MVAR).
   It is usually labelled something like "Load C" or "Bus 8 Load".

3. **Split the load into two equal halves:**
   - Copy the load block (Ctrl+C, Ctrl+V).
   - Set each copy to **50 MW / 17.5 MVAR** (half of 100 MW / 35 MVAR).
   - Connect both halves in parallel to the same Bus 8 node.

4. **Add a Three-Phase Breaker in series with one half:**
   - Insert a Three-Phase Breaker block between Bus 8 and one of the 50 MW load copies.
   - Set the breaker parameters:
     - Initial state: **closed** (1)
     - Switching times: `[ct]`  (opens at t = 5/60 s = 0.0833 s)
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

1. On Kaggle, create a new notebook and attach the `simulink-outputs` dataset.

2. Update the `MAT_PATH` variable in each notebook to point to the dataset:
   ```python
   MAT_PATH = '/kaggle/input/simulink-outputs/scenario_1_simulink_outputs.mat'
   ```

3. Run **`pinn_simulink/pinn-simulink-scenario-1.ipynb`** for Scenario 1.

4. Run **`pinn_simulink/pinn-simulink-scenario-2.ipynb`** for Scenario 2.

5. Each notebook produces:
   - `results_detailed.csv` — full trajectory comparison table
   - `summary_statistics.txt` — error metrics
   - Plots: Simulink reference, PINN output, comparison, error analysis

---

## Verification Checklist

| Check | Expected |
|-------|----------|
| G1 Reactances1 after fix | `[0.3614, 0.1505, 0.1505, 0.2399, 0.2399, 0.2399, 0.0832]` |
| Load flow initial angles | G1≈2.27°, G2≈19.73°, G3≈13.18° (±0.5°) |
| IC offset in run_scenarios.m | < 1.0° per generator |
| Quickcheck plot (S1) | Oscillating angles, fault cleared at ~0.083 s |
| delta_ref[0] in PINN notebook | Matches expected initial angles |
| PINN data_loss decreasing | Should drop over training iterations |

---

## File Reference

```
pinn_simulink/
├── matlab/
│   ├── IEEE_9bus_new_wow_mach_9.slx   ← Base model (fix G1 Reactances1 here)
│   ├── run_scenarios.m                ← Main simulation script (NEW, use this)
│   ├── check_model_params.m           ← Diagnostic script (read-only)
│   └── [old scripts — ignore]         setup_scenario_*.m, wire_workspace_blocks.m
├── pinn_rk4/
│   ├── pinn-scenario-1-final.ipynb    ← Phase 1 (RK4 reference) — complete
│   └── pinn-scenario-2-final.ipynb    ← Phase 1 (RK4 reference) — complete
└── pinn_simulink/
    ├── pinn-simulink-scenario-1.ipynb ← Phase 2 (Simulink reference) — NEW
    └── pinn-simulink-scenario-2.ipynb ← Phase 2 (Simulink reference) — NEW
```
