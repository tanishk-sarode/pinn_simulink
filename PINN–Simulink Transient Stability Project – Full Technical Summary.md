# PINN–Simulink Transient Stability Project – Full Technical Summary
## 1. Project goals and high‑level architecture
This project builds an end‑to‑end pipeline to study transient stability of the IEEE 9‑bus, 3‑machine system under two disturbance scenarios using both classical simulation (Simulink) and Physics‑Informed Neural Networks (PINNs). The ultimate goal is to show that PINNs can learn the swing‑equation dynamics closely enough to match a high‑fidelity Simulink model, and to provide tooling for systematic comparison and visualization.

At a high level, the workflow is:

1. Start from the original Simulink model `IEEE_9bus_new_wow_mach_9.slx` and automatically generate *scenario‑specific* models `scenario_1.slx` (three‑phase fault at Bus 7) and `scenario_2.slx` (50% load outage at Bus 8) using MATLAB setup scripts.
2. Wire the internal generator state signals (rotor angles and speed deviations) to `To Workspace` blocks, again using an automated MATLAB script.
3. Run the Simulink models with a standardized time grid and export the trajectories as `.mat` files (`scenario_1_simulink_outputs.mat`, `scenario_2_simulink_outputs.mat`) containing time vector `T_ref` and arrays `delta_sim_i`, `omega_sim_i` already on that grid.
4. Train PINNs in Kaggle notebooks for each scenario (
   - RK4 vs PINN: classical swing‑equation integrator as reference,
   - Simulink vs PINN: Simulink trajectory as reference), using the same swing‑equation physics and admittance matrices but different data anchors.
5. Optionally train a small neural network surrogate that emulates the Simulink trajectories directly (for fast approximate evaluation), and convert PINN `.npz` outputs into `.mat` for MATLAB‑side comparison and plotting.
6. Use a Python comparison script to jointly visualize and quantify errors between RK4, PINN, and Simulink for both scenarios.

The rest of this document walks through each component in detail and explains how they fit together.

***
## 2. Simulink scenario setup scripts
### 2.1 `setup_scenario_1.m` – Three‑phase fault at Bus 7
This script creates and configures `scenario_1.slx` starting from the base IEEE‑9‑bus model.

Key responsibilities:

- **Model duplication and loading**:
  - Copies `IEEE_9bus_new_wow_mach_9.slx` to `scenario_1.slx` if it does not already exist.
  - Loads `scenario_1` into memory with `load_system` for further modification.
- **Pre‑load configuration**:
  - Sets a `PreLoadFcn` callback that defines `ct = 5/60;`, where `ct` is the fault clearing time in seconds (5 cycles at 60 Hz).
- **Simulation horizon**:
  - Sets `StopTime` to `2.0` seconds, which aligns with the PINN time horizon and the standard reference grid.
- **Breaker timing hard‑coding**:
  - Removes runtime dependence on `ct` by directly setting `SwitchTimes` for the disturbance and associated breakers:
    - `Three-Phase Fault` gets `SwitchTimes = '[1/600, 5/60]'`, turning the fault on near `t = 0` and clearing it at `ct`.
    - `Three-Phase Breaker` and `Three-Phase Breaker1` also receive `SwitchTimes = '[1/600, 5/60]'`, ensuring consistent pre‑fault, fault, and post‑fault network configurations.
  - Each `set_param` call is wrapped in `try/catch` blocks so that missing blocks produce warnings rather than hard errors.
- **To‑Workspace logging blocks**:
  - Ensures six `To Workspace` blocks exist, with variable names:
    - `delta1_sim`, `delta2_sim`, `delta3_sim` (rotor angles in degrees)
    - `omega1_sim`, `omega2_sim`, `omega3_sim` (speed deviations in per‑unit)
  - Blocks are created with `SaveFormat = 'Timeseries'` and placed at sensible positions in the model diagram.
- **Persistence**:
  - Saves `scenario_1.slx` and prints a message directing the user to run `wire_workspace_blocks.m` next.

This script makes Scenario 1 fully reproducible: simply run it once and the resulting model is ready for automated wiring and simulation.
### 2.2 `setup_scenario_2.m` – 50% load outage at Bus 8
The `setup_scenario_2.m` script configures `scenario_2.slx` for a 50% load outage at Bus 8 around the same clearing time `ct = 5/60`.

Major steps:

- **Model duplication and loading**:
  - Copies `IEEE_9bus_new_wow_mach_9.slx` to `scenario_2.slx` if needed, then loads `scenario_2` with `load_system`.
- **Pre‑load configuration**:
  - Sets `PreLoadFcn` to define `ct = 5/60;`, and logs its value to the console.
- **Simulation horizon**:
  - Sets `StopTime = '2.0'` seconds.
- **Bus‑8 load modification (manual intervention)**:
  - Enumerates all `SubSystem` blocks and prints them so that the user can visually identify the Bus 8 load subsystem that corresponds to 125 MW / 50 MVAR.
  - Prints explicit guidance:
    - Locate the Bus 8 load.
    - Insert a `Three-Phase Breaker` such that **half** of the Bus 8 load is placed behind it.
    - Configure the breaker to open at `t = ct` (the script notes that `SwitchTimes = [ct]` is implied by the `PreLoadFcn`).
  - This step is intentionally semi‑automatic because the exact block structure and naming in the user’s Simulink model can vary, and reliable programmatic surgery on arbitrary load subsystems is brittle.
- **To‑Workspace logging blocks**:
  - Adds or reuses the same six `To Workspace` blocks (`delta1_sim`/`omega1_sim`, etc.) as in Scenario 1, with identical configuration.
- **Persistence**:
  - Saves `scenario_2.slx` and reminds the user to run `wire_workspace_blocks.m` next with `mdl = 'scenario_2'`.

In summary, Scenario 2 is structurally similar to Scenario 1 but changes the disturbance from a bus fault to a timed load outage; the final wiring and data‑logging pattern remain consistent.

***
## 3. Automatic wiring of generator signals to the workspace
### 3.1 `wire_workspace_blocks.m`
This script automatically connects generator‑level rotor angles and speed deviation signals from BusSelector blocks to the `To Workspace` sinks created in the setup scripts.

Design and logic:

- **Model selection**:
  - The script defines `mdl = 'scenario_1';` by default, with a comment instructing the user to change this to `'scenario_2'` when wiring the second scenario.
- **BusSelector detection**:
  - It searches for all blocks of type `BusSelector` in the model.
  - For each BusSelector, it attempts to read the `OutputSignals` parameter; if that string contains both `delta` and `dw`, the block is treated as a generator signal aggregator and added to a `gen_bs` list.
  - The script asserts that exactly three such blocks exist (for the three generators), otherwise it throws an error prompting the user to check the model.
- **Generator assignment**:
  - Because BusSelector names and order may vary, the script uses content‑based heuristics:
    - If `OutputSignals` starts with `Load angle`, the block is considered G2.
    - Among the remaining two BusSelectors, the one whose name contains `'3'` is mapped to G3, and the other to G1.
  - This yields a mapping `gen_assign(k)` giving the generator index (1, 2, or 3) for each BusSelector block `gen_bs{k}`.
- **Connection drawing**:
  - For each generator:
    - It parses `OutputSignals`, splits into individual signal names, and finds the port index of the `delta` and `dw` signals.
    - It constructs source port strings like `'<BusSelectorName>/<portIndex>'` and destination sink names matching the `To Workspace` blocks (`delta1_sim`, `omega1_sim`, etc.).
    - It calls `add_line` with `autorouting = 'on'` to connect each source port to the corresponding sink. Any errors (e.g., existing connections) are logged as warnings, not fatal.
- **Persistence**:
  - After wiring all three generators, the script calls `save_system(mdl)` and prints a completion message.

With this wiring script, the only manual work in Simulink is configuring the Scenario 2 Bus‑8 load outage. Everything else (creation of scenario models, logging blocks, and signal routing) is automated.

***
## 4. Simulink simulation and export
### 4.1 `run_simulation.m`
`run_simulation.m` is a generic driver script that runs either scenario, interpolates outputs onto a uniform time grid, converts units to match the PINN formulation, and saves everything into a single `.mat` file per scenario.

Core behavior:

- **Scenario selection and configuration**:
  - The top of the script defines `scenario = 1; % <-- SET TO 1 OR 2` so the user (or workflow) can pick Scenario 1 or 2 explicitly.
  - It builds the model name dynamically as `mdl = sprintf('scenario_%d', scenario);` and chooses common simulation parameters:
    - Clearing time `t_fault_clear = 5/60;` (also the load‑outage time in Scenario 2).
    - Total horizon `t_end = 2.0` seconds.
    - Reference time step `dt_ref = 5e-4`, resulting in `T_ref` of length 4001 over `[0, 2]` seconds.
- **Workspace parameter safety**:
  - It defines `ct = 5/60;` in the base workspace and logs it. Although breaker `SwitchTimes` are now hardcoded in the setup scripts, this acts as a safety net if any block still references `ct`.
- **Running the Simulink model**:
  - Loads the appropriate scenario model with `load_system(mdl)`.
  - Runs `sim(mdl, 'StopTime', num2str(t_end))`, timing the execution and printing runtime.
- **Extracting logged signals**:
  - Reads `delta1_sim`, `delta2_sim`, `delta3_sim`, and their `Time` vector from the returned `sim_out` object.
  - Reads `omega1_sim`, `omega2_sim`, `omega3_sim` similarly.
  - Verifies the number of `t_sim` samples and constructs `delta_sim` and `omega_sim` as `(N × 3)` matrices.
- **Unit conversion to PINN conventions**:
  - Converts rotor angles from degrees to radians: `delta_sim_rad = deg2rad(delta_sim);`.
  - Computes synchronous speed `omega_s = 2 * pi * 60;` and converts per‑unit speed deviations to physical `rad/s` as `omega_sim_rads = omega_sim * omega_s;`.
- **Interpolation to `T_ref`**:
  - Uses `interp1` with linear interpolation to generate `delta_sim_i` and `omega_sim_i` on the uniform `T_ref` grid used by the PINN notebooks.
- **Saving outputs**:
  - Writes a scenario‑specific `.mat` file (e.g., `scenario_1_simulink_outputs.mat`) containing:
    - `T_ref` (4001×1)
    - `delta_sim_i` (4001×3, radians)
    - `omega_sim_i` (4001×3, rad/s)
    - `t_sim`, `delta_sim_rad`, `omega_sim_rads` as auxiliary data.
- **Quick diagnostic plotting**:
  - Plots three rotor‑angle traces and three speed‑deviation traces against `T_ref`, draws a vertical line at `t_fault_clear`, and saves a PNG quick‑check figure (e.g., `scenario_1_simulink_quickcheck.png`).

This script is the definitive source of the reference time grid and units that all downstream Python code expects.

***
## 5. Python tooling around Simulink and PINN outputs
### 5.1 `npz_to_mat.py` – Converting PINN `.npz` to `.mat`
This script converts saved PINN numpy archives into `.mat` files, enabling MATLAB‑side analysis using the same comparison and plotting infrastructure as Simulink.

Behavior:

- **Purpose and usage**:
  - Designed to be run once per experiment after PINN training:
    - `python npz_to_mat.py` in the folder containing the scenario‑specific output directories.
- **Configuration structure**:
  - Defines a list `conversions` where each entry holds:
    - `scenario`: 1 or 2.
    - `folder`: path to the scenario’s PINN output directory (e.g., `scenario_1_baseline_outputs_improved`, `scenario_2_load_outage_outputs_ultimate`).
    - `pinn_npz`: filename of the numpy archive containing PINN outputs (typically `pinn_outputs.npz`).
    - `ref_npz`: filename for the reference outputs (usually `reference_outputs.npz`).
- **Per‑scenario processing**:
  - Checks that `folder` exists; otherwise prints a `[SKIP]` message.
  - If `pinn_outputs.npz` exists:
    - Loads `T_eval`, `delta_pinn`, `omega_pinn` from the archive.
    - Writes a `.mat` file `pinn_outputs.mat` with those arrays, allowing MATLAB to load them easily.
  - If `reference_outputs.npz` exists:
    - Loads `T_ref`, `delta_ref`, `omega_ref` and writes `reference_outputs.mat` with the same naming convention the comparison script expects.
  - At the end it prints `Done. You can now load these .mat files from MATLAB.`

This script bridges the Python and MATLAB worlds so that PINN results can be treated just like any Simulink trajectory.
### 5.2 `compare_pinn_simulink.py` – Joint error analysis and plotting
The `compare_pinn_simulink.py` script performs an integrated comparison between three sources for each scenario:
1. RK4 reference solution exported from the PINN notebook.
2. PINN solution evaluated on its training/evaluation grid.
3. Simulink solution from `run_simulation.m`.

Key design elements:

- **Command‑line interface**:
  - Without arguments, it runs both scenarios in sequence.
  - With `--sc 1` or `--sc 2`, it restricts analysis to a single scenario.
- **Directory and label configuration**:
  - `PINN_DIRS` maps scenario numbers to the respective PINN output folders:
    - `1 → 'scenario_1_baseline_outputs_improved'`
    - `2 → 'scenario_2_load_outage_outputs_ultimate'`.
  - `SC_LABELS` provides human‑readable descriptions for each scenario for plot titles and logs (fault vs load outage).
  - `T_FAULT_CLEAR` is fixed at `5.0 / 60.0` to mark the disturbance clearing time on plots.
- **Loading helpers**:
  - `load_pinn(scenario)` loads `pinn_outputs.npz` and `reference_outputs.npz` from the appropriate folder and returns:
    - `T_eval`, `delta_pinn`, `omega_pinn`, `delta_ref`, `omega_ref` (with all arrays converted to `float64`).
  - `load_simulink(scenario)` loads `scenario_N_simulink_outputs.mat` and returns `T_ref`, `delta_sim_i`, `omega_sim_i` for that scenario.
- **Metric computation**:
  - `print_metrics(...)` first interpolates Simulink trajectories to the PINN time grid `T` for all three generators.
  - It then computes, for each generator:
    - Mean and maximum absolute rotor‑angle error between PINN and Simulink (in degrees).
    - Mean absolute rotor‑angle error between RK4 and Simulink.
    - Mean absolute rotor‑angle error between PINN and RK4.
  - A formatted table is printed summarizing all four metrics per generator.
- **Comparison plots**:
  - `plot_comparison(...)` generates a 3×2 grid of subplots:
    - Left column: rotor angles for G1–G3 in degrees, overlaying RK4 (solid blue), PINN (dashed red), and Simulink (dotted green), with a vertical line at the clearing time.
    - Right column: speed deviations in rad/s for G1–G3, with the same legend semantics.
  - Figure is titled with the scenario label and a subtitle `Rotor Angle & Speed: RK4 vs PINN vs Simulink` and saved as `scenario_N_full_comparison.png`.
- **Error‑focused plots**:
  - `plot_error(...)` generates a 1×2 subplot figure:
    - Left: time evolution of |Δδ| between PINN and Simulink for all three generators.
    - Right: time evolution of |Δδ| between RK4 and Simulink, again for all generators.
  - Both subplots include the clearing time line and legends, and the figure is saved as `scenario_N_error_analysis.png`.

This script is the main diagnostic tool to understand where the PINN agrees or disagrees with Simulink and with the RK4 baseline, both in time and across machines.
### 5.3 `pinn-simulink-senario-1.ipynb` – Simple Simulink surrogate (Scenario 1)
This smaller notebook trains a dense neural network directly on the Simulink outputs for Scenario 1 to act as a fast surrogate for the full Simulink model, without enforcing physics explicitly.

Core structure:

- **Data loading**:
  - Loads `scenario_1_simulink_outputs.mat` from a Kaggle dataset path.
  - Prints keys and shapes to confirm presence of `T_ref`, `delta_sim_i`, and `omega_sim_i` (4001×1, 4001×3, 4001×3).
- **Model definition**:
  - Concatenates rotor angles and speeds into a single target array of shape `(4001, 6)`.
  - Normalizes time as `t_norm = t_data - 1.0`, effectively centering the domain around zero.
  - Defines `SimulinkEmulator`, a 1D input → 6D output network:
    - Architecture: `Linear(1,128) → Tanh → Linear(128,128) → Tanh → Linear(128,128) → Tanh → Linear(128,6)`.
    - Uses Adam optimizer with `lr = 2e-3` and a StepLR scheduler that halves the learning rate every 2000 steps.
- **Training loop**:
  - Trains for 8000 epochs, minimizing a standard MSE loss `MSE(model(t_norm), target_data)`.
  - Logs loss values every 1000 epochs; loss decays from around `4.0e-01` to `≈5.5e-04` over ~66 seconds on GPU.
- **Evaluation and visualization**:
  - Runs the trained model in eval mode to generate predicted trajectories for all six outputs.
  - Plots Simulink vs NN surrogate for each generator’s rotor angle and speed in a 3×2 grid, marking the clearing time at `5/60` seconds.
  - Saves the figure to `scenario_1_nn_surrogate.png` in Kaggle’s working directory.

This notebook demonstrates that a purely data‑driven surrogate can closely mimic Simulink for a single scenario; the PINNs extend this by incorporating physics and handling multiple configurations.

***
## 6. PINN notebooks and physics‑informed modeling
### 6.1 `pinn-scenario-2-final.ipynb` – RK4 vs PINN for Scenario 2
This notebook implements a full PINN solver for Scenario 2 using a classical RK4 time‑stepping solution of the swing equations as the reference trajectory.

Core components:

- **Configuration and hyperparameters**:
  - Uses GPU acceleration if available and logs visible GPU devices.
  - Simulation parameters:
    - Frequency `f = 60.0 Hz`, synchronous speed `w_s = 2πf`.
    - Clearing time `t_fault_clear = 5.0 / 60.0`.
    - Final time `t_end = 2.0 s`.
  - Network architecture:
    - Hidden width 512, depth 8, `Tanh` activations, Xavier normal initialization for weights, zero biases.
  - Training data allocations:
    - Random collocation points: `N_C_BASE = 25000`.
    - Extra collocation around the clearing time: `N_C_FAULT = 8000` uniformly in a ±0.05 s window.
    - Extra early‑time collocation: `N_C_EARLY = 6000` on `[0, 0.2]`.
    - IC points at `t = 0`: `N_IC = 512`.
    - Data anchors from the reference trajectory: `N_DATA = 600` sampled uniformly in time.
  - Loss weights:
    - PDE residual: `PDE_LOSS_WEIGHT = 4.0`.
    - Initial conditions: `IC_LOSS_WEIGHT = 10.0`.
    - Data term: `DATA_LOSS_WEIGHT = 0.8`.
  - Training loop:
    - `NUM_ITERS = 30000` Adam iterations with ReduceLROnPlateau scheduler on the total loss.

- **System parameters and admittance matrices**:
  - Inertia constants `H = [23.64, 6.40, 3.01]`, mechanical power inputs `Pm = [0.716, 1.63, 0.85]`, and internal voltages `E = [1.0566, 1.0502, 1.0170]` are defined.
  - Initial rotor angles `delta0_deg = [2.1500, 18.9000, 12.5000]` are converted to radians and initial speed deviations `omega0` are set to zero.
  - Equivalent masses `M = 2H / w_s` are computed.
  - Two 3×3 complex admittance matrices `Y_fault` and `Y_clear` are constructed from real and imaginary parts (G and B) for the faulted and cleared network topologies.
  - The function `piecewise_Y(t)` returns `Y_fault` when `t < t_fault_clear` and `Y_clear` otherwise, allowing time‑varying electrical power injection.

- **Classical RK4 reference**:
  - A function `rk4_step` implements a standard fourth‑order Runge–Kutta integrator for the swing equations, internally using `piecewise_Y` and `electrical_power` to obtain `Pe` at each stage.
  - A reference solution is generated over `[0, t_end]` at step size `dt_rk4 = 5e-4`, producing arrays `T_ref`, `delta_ref`, and `omega_ref` of shapes `(4001,)`, `(4001,3)`, and `(4001,3)` respectively.

- **PINN architecture**:
  - The `PINN` class maps scalar times `t` (1D input) to six outputs (three rotor angles and three speed deviations).
  - To enforce initial conditions softly, the network outputs `y` are transformed as:
    - `delta(t) = delta0 + t * delta_raw(t)`
    - `omega(t) = omega0 + t * omega_raw(t)`
    where `delta_raw` and `omega_raw` are the raw outputs and `delta0`, `omega0` are ICs.
  - The final model is optionally wrapped in `nn.DataParallel` to use multiple GPUs when available.

- **Training data construction**:
  - Collocation set `t_c` is formed by concatenating random points over `[0, t_end]` with dense windows around the clearing time and early transient, then shuffling.
  - IC times `t_ic` are all zeros.
  - Data times `t_data` are selected as a uniform subsample of `T_ref` using `N_DATA` indices, and corresponding `delta_data`, `omega_data` slices are extracted.

- **Loss function**:
  - The `pinn_loss()` function:
    - Evaluates the PINN at collocation points and computes time derivatives of each state using `torch.autograd.grad`.
    - Builds kinetic residuals `ddelta_dt - omega` and dynamic residuals corresponding to the swing equations using `Pe = electrical_power(delta, E_d, Yb)`.
    - Computes a PDE loss as mean‑squared residuals for both equations.
    - Enforces initial conditions by running the network at `t_ic` and penalizing deviations from `delta0` and `omega0`.
    - Enforces data consistency by comparing `delta`, `omega` at `t_data` to `delta_data`, `omega_data` with the specified `DATA_LOSS_WEIGHT`.
    - Combines these into a single scalar loss: `total_loss = PDE_LOSS_WEIGHT*loss_pde + IC_LOSS_WEIGHT*ic_loss + data_loss`.

- **Training and outputs**:
  - The training loop reports loss breakdowns and ranges of delta/omega periodically, helping to detect divergence or saturation.
  - After training, the notebook evaluates the PINN on `T_ref`, computes errors against RK4, and saves:
    - `reference_outputs.npz` (time and RK4 trajectory)
    - `pinn_outputs.npz` (time and PINN trajectory)
    - `summary_metrics.npz`, a CSV `results_detailed.csv`, and textual statistics summarizing errors.
  - Plots compare rotor angles and speeds, and error traces over time.

This notebook is the baseline for Scenario 2 before introducing Simulink as an alternative data source.
### 6.2 `pinn-scenario-1-simulink-final-1.ipynb` – Scenario 1 PINN with Simulink reference
The Scenario 1 Simulink notebook is structurally similar to the Scenario 2 RK4 notebook but uses Simulink output as `delta_ref` and `omega_ref` instead of RK4, and adopts more “physics‑balanced” hyperparameters and collocation sampling.

Key differences and improvements:

- **Reference data source**:
  - Loads `scenario_1_simulink_outputs.mat` via `scipy.io.loadmat`, extracting:
    - `T_ref` (4001,),
    - `delta_sim_i` and `omega_sim_i` as `delta_ref`, `omega_ref`, representing the Simulink swing trajectory for Scenario 1.
- **Hyperparameter rebalancing**:
  - PINN architecture is kept at 512×8 with Xavier initialization.
  - Training data allocations change to:
    - `N_C_BASE = 16000`, `N_C_FAULT = 16000`, `N_C_EARLY = 8000`.
    - `N_IC = 256`, `N_DATA = 2000`.
  - Loss weights are updated to:
    - `PDE_LOSS_WEIGHT = 0.5`, `IC_LOSS_WEIGHT = 1.0`, `DATA_LOSS_WEIGHT = 5.0`, shifting more emphasis to physics than in an earlier version that had extremely small PDE weight and very large data weight.
  - Training iterations `NUM_ITERS = 17000` are used.
- **Collocation resampling**:
  - The collocation set is deliberately oversampled in two critical regions:
    - A dense band around clearing time with `fault_window = 0.03` seconds on either side of `t_fault_clear`.
    - The early transient interval `[0, 0.2]` seconds.
  - Combined with random base points and shuffling, this ensures the optimizer sees many physics residuals exactly where the dynamics are fastest and hardest to fit.

The rest of the notebook mirrors the loss structure and evaluation pipeline used elsewhere (IC encoding, autograd for time derivatives, training, plotting, and saving statistics), but now “Simulink vs PINN” is the primary comparison rather than “RK4 vs PINN.”
### 6.3 Scenario 2 Simulink‑anchored PINN notebook
The Scenario 2 Simulink‑anchored notebook (which you derived from `pinn-scenario-2-final.ipynb` and the Scenario 1 Simulink notebook) follows the same pattern:

- Keeps the **Scenario 2 system parameters and admittance matrices** exactly as in `pinn-scenario-2-final.ipynb`.
- Retains the **Scenario 2 hyperparameters** optimized for the load‑outage case:
  - `N_C_BASE = 25000`, `N_C_FAULT = 8000`, `N_C_EARLY = 6000`.
  - `N_IC = 512`, `N_DATA = 600`.
  - `PDE_LOSS_WEIGHT = 4.0`, `IC_LOSS_WEIGHT = 10.0`, `DATA_LOSS_WEIGHT = 0.8`, `NUM_ITERS = 30000`.
- **Replaces the RK4 reference section** with a Simulink loader analogous to Scenario 1:
  - Loads `scenario_2_simulink_outputs.mat` from your Kaggle dataset.
  - Sets `T_ref`, `delta_ref`, `omega_ref` from `T_ref`, `delta_sim_i`, and `omega_sim_i` in the `.mat` file.
- Leaves the **PINN class, loss function, and training loop** unchanged, so training is now directly guided by Simulink’s load‑outage trajectory instead of a pure RK4 solution.

Once trained, this notebook will enable comparisons of `PINN vs Simulink` for the load‑outage case, and its `.npz` outputs can be converted to `.mat` via `npz_to_mat.py` for use in `compare_pinn_simulink.py`.

***
## 7. Putting it all together – End‑to‑end workflow
The full workflow from Simulink model to PINN analysis and back can be summarized as follows:

1. **Prepare Simulink scenarios**:
   - Run `setup_scenario_1.m` to create and configure `scenario_1.slx` with hardcoded fault and breaker switch times and logging blocks.
   - Run `setup_scenario_2.m` to create and configure `scenario_2.slx`, then manually modify the Bus 8 load subsystem to implement a 50% outage at `ct`, and add the required breaker.

2. **Wire generator signals**:
   - For each scenario, set `mdl = 'scenario_1'` or `'scenario_2'` in `wire_workspace_blocks.m` and run it to connect BusSelector outputs (delta and `dw`) to `delta*_sim` and `omega*_sim` `To Workspace` sinks.

3. **Generate reference trajectories**:
   - Run `run_simulation.m` with `scenario = 1` and then `scenario = 2` to produce `scenario_1_simulink_outputs.mat` and `scenario_2_simulink_outputs.mat`; inspect the quick‑check PNGs to ensure the rotor‑angle and speed trajectories look reasonable.

4. **Train PINNs in Kaggle notebooks**:
   - For RK4‑anchored runs, use `pinn-scenario-1-final.ipynb` and `pinn-scenario-2-final.ipynb` (Scenario 2 case fully detailed above) to obtain `reference_outputs.npz` and `pinn_outputs.npz` per scenario.
   - For Simulink‑anchored runs, use `pinn-scenario-1-simulink-final-1.ipynb` and the analogous Scenario 2 Simulink notebook to load `.mat` files, reset `T_ref`, `delta_ref`, `omega_ref`, and retrain the PINNs with the chosen hyperparameters.

5. **Convert PINN results for MATLAB**:
   - Run `npz_to_mat.py` once to write `pinn_outputs.mat` and `reference_outputs.mat` into each scenario’s output folder, mirroring the array names expected by MATLAB.

6. **Perform joint comparison and visualization**:
   - Run `compare_pinn_simulink.py` from Python to produce numerical error summaries and multi‑panel PNGs of RK4 vs PINN vs Simulink across both scenarios.
   - Optionally, load `pinn_outputs.mat` and `reference_outputs.mat` directly into MATLAB for further custom analysis or plotting.

7. **Optional surrogate training for Scenario 1**:
   - Use `pinn-simulink-senario-1.ipynb` to train a compact neural surrogate of the Simulink output, which can help in rapid what‑if exploration or as a baseline for purely data‑driven models.

At this point, the project contains a complete, reproducible experimental stack: from automated Simulink scenario construction through physics‑informed learning and back to unified error analysis.

***
## 8. Key design choices and lessons
Several design decisions were important for stability, accuracy, and maintainability:

1. **Single source of truth for the time grid and units**:
   - `run_simulation.m` enforces a 4001‑point uniform grid `[0, 2]` seconds at `dt = 5e-4` and converts units to radians and rad/s. Both the PINN notebooks and the comparison script assume and reuse these conventions.

2. **Automated but inspectable Simulink transformations**:
   - Scenario setup and wiring scripts avoid fragile hard‑coded block indices by using model names and `find_system` with content‑based heuristics. Where exact structure is too variable (e.g., Bus‑8 load split), the scripts print actionable guidance instead of trying to be over‑smart.

3. **Balanced PINN losses and focused collocation**:
   - Early versions over‑weighted data loss and under‑weighted PDE residuals, leading to over‑smoothed solutions that failed to capture sharp fault transients. The revised hyperparameters and collocation strategies explicitly increase PDE weight and oversample around clearing times and early transients, which substantially improves fidelity in difficult regions.

4. **Bidirectional MATLAB–Python interoperability**:
   - The consistent use of `.mat` and `.npz` formats, combined with `npz_to_mat.py` and the comparison script, ensures that data can move freely between environments without renaming arrays or manually re‑implementing logic.

5. **Scenario‑agnostic comparison tooling**:
   - `compare_pinn_simulink.py` is written once and parameterized by scenario ID and directory mappings, so adding new experiments is as simple as extending `PINN_DIRS`, `SC_LABELS`, and ensuring the correct `.mat` and `.npz` assets exist.

These choices make the project flexible for further scenarios (e.g., different fault locations or load shedding patterns) and for future experiments such as multi‑scenario training or transfer learning between fault types.