%% =========================================================
% SETUP SCRIPT — scenario_2.slx
% Scenario 2: 50% Load Outage at Bus 8
% Outage/disconnect time: 5/60 s (~0.0833 s, 5 cycles)
% t_end = 2.0 s | dt_ref = 5e-4 s | 4001 time points
% RUN THIS SCRIPT FROM THE FOLDER CONTAINING:
%   IEEE_9bus_new_wow_mach_9.slx
% =========================================================

clear; clc;

src_model = 'IEEE_9bus_new_wow_mach_9';
mdl       = 'scenario_2';

%% ---- STEP 1: Copy original model ----
if ~exist([mdl '.slx'], 'file')
    copyfile([src_model '.slx'], [mdl '.slx']);
    fprintf('[OK] Copied %s.slx -> %s.slx\n', src_model, mdl);
else
    fprintf('[SKIP] %s.slx already exists\n', mdl);
end

%% ---- STEP 2: Load model ----
load_system(mdl);
fprintf('[OK] Loaded %s\n', mdl);

%% ---- STEP 3: PreLoadFcn ----
% 'ct' = load outage / disconnect time (same variable name as Scenario 1
%         so run_simulation.m stays generic)
set_param(mdl, 'PreLoadFcn', 'ct = 5/60;');
fprintf('[OK] PreLoadFcn set: ct = 5/60 = %.5f s (load outage time)\n', 5/60);

%% ---- STEP 3.5: Fix G1 (247.5 MVA) machine parameters to IEEE 9-bus standard values ----
% Diagnostic showed G1 has placeholder Reactances1=[31..37], PolePairs=20 (hydro),
% RotorType=Salient-pole. These corrupt the load-flow and admittance matrix used
% by Pe, making dynamics wrong even if initial angles are forced to RK4 values.
%
% Correct values: Anderson & Fouad IEEE 9-bus, machine base (pu on 247.5 MVA, 16.5 kV)
%   [Xd, Xd', Xd'', Xq, Xq', Xq'', Xl] = [0.8958, 0.1198, 0.0969, 0.8645, 0.1198, 0.0969, 0.0521]
%   PolePairs = 1 (steam turbine, 3600 rpm, 60 Hz)
%   RotorType = Round

% Find all synchronous machine blocks (reused by Step 5.5 below)
mach_blocks = [
    find_system(mdl, 'MaskType', 'Synchronous Machine');
    find_system(mdl, 'MaskType', 'Synchronous Machine (Simplified)');
    find_system(mdl, 'RegExp', 'on', 'MaskType', '.*ynchronous.*achine.*')
];
mach_blocks = unique(mach_blocks);

% Locate the 247.5 MVA block (G1)
g1_block = '';
for bi = 1:numel(mach_blocks)
    if contains(mach_blocks{bi}, '247')
        g1_block = mach_blocks{bi};
        break;
    end
end

if isempty(g1_block)
    fprintf('[WARN] G1 (247.5 MVA) block not found — fix Reactances1 manually.\n');
    fprintf('         Reactances1 = [0.8958 0.1198 0.0969 0.8645 0.1198 0.0969 0.0521]\n');
else
    fprintf('[OK] Found G1 block: %s\n', g1_block);
    % NOTE: Do NOT change RotorType or PolePairs — this old SimPowerSystems
    % block's mask init crashes if RotorType is switched programmatically.
    % Fixing Reactances1 (was [31..37] placeholder) is sufficient to correct
    % the load-flow solution and match RK4 dynamics.
    %
    % Reactances [Xd Xd' Xd'' Xq Xq' Xq'' Xl] — machine base pu (Anderson & Fouad IEEE 9-bus)
    correct_react = '[0.8958, 0.1198, 0.0969, 0.8645, 0.1198, 0.0969, 0.0521]';
    try
        set_param(g1_block, 'Reactances1', correct_react);
        fprintf('[OK] G1 Reactances1 = %s\n', correct_react);
    catch e3
        fprintf('[WARN] G1 Reactances1: %s\n', e3.message);
        fprintf('       Open model manually and set Reactances1 to %s\n', correct_react);
    end
end
fprintf('\n');

%% ---- STEP 4: Simulation stop time ----
set_param(mdl, 'StopTime', '2.0');
fprintf('[OK] StopTime = 2.0 s\n');

%% ---- STEP 4.5: Disable Three-Phase Fault block only (NOT breakers) ----
% Scenario 2 is a load outage implemented via a breaker on the Bus 8 load.
% The Three-Phase Fault block was copied from the base model and causes a
% "Transition times must be in increasing order" error — disable it only.
% Breakers must remain active so the Bus 8 load-outage breaker still works.
fault_blocks = find_system(mdl, 'RegExp', 'on', 'Name', '.*[Ff]ault.*');
disabled_count = 0;
for fi = 1:length(fault_blocks)
    try
        set_param(fault_blocks{fi}, 'Commented', 'on');
        fprintf('[OK] Disabled fault block: %s\n', fault_blocks{fi});
        disabled_count = disabled_count + 1;
    catch e
        fprintf('[WARN] Could not disable %s: %s\n', fault_blocks{fi}, e.message);
    end
end
if disabled_count == 0
    fprintf('[INFO] No Three-Phase Fault blocks found.\n');
else
    fprintf('[OK] Disabled %d fault block(s) — breakers left active for load outage.\n', disabled_count);
end

%% ---- STEP 5: Locate Bus 8 load blocks for the 50% outage ----
%
% This step CANNOT be fully automated because the exact block name
% depends on your Simulink model layout.  Use the printed list below
% to find the Bus 8 load block(s), then do the manual wiring in Simulink.
%
% IEEE 9-bus Bus 8 load standard values: 125 MW + 50 MVAR
% "50% outage" means disconnecting 62.5 MW + 25 MVAR.
%
% MANUAL STEPS TO PERFORM AFTER RUNNING THIS SCRIPT:
%   1. Open scenario_2.slx in Simulink.
%   2. Find the block(s) that represent the Bus 8 load
%      (look for "Load" + "Bus 8" in the name, or a
%       Three-Phase Parallel/Series RLC Load with 125 MW).
%   3. Split that load into two equal halves (copy the block, halve
%      each one's MW/MVAR parameters to 62.5 MW + 25 MVAR each).
%   4. Insert a Three-Phase Breaker in SERIES with one of the halves.
%      Breaker settings:
%        - Initial state:  closed   (1 = closed)
%        - Switching times: [ct]    (opens at t = 5/60 s)
%        - Transition:      open
%   5. Save and close the model.
% -----------------------------------------------------------------

fprintf('\n[INFO] Searching for load-related blocks near Bus 8...\n');

% Try to find any block with 'Load' and '8' in its name
all_blocks = find_system(mdl, 'SearchDepth', 3);
fprintf('Blocks containing "Load" and "8" in name:\n');
found = false;
for i = 1:length(all_blocks)
    blk = all_blocks{i};
    if contains(blk,'Load','IgnoreCase',true) && ...
       contains(blk, '8')
        fprintf('  -> %s\n', blk);
        found = true;
    end
end
if ~found
    fprintf('  (none matched – list all SubSystem blocks below)\n');
    all_ss = find_system(mdl, 'BlockType', 'SubSystem');
    for i = 1:length(all_ss)
        fprintf('  %s\n', all_ss{i});
    end
end

fprintf('\n[ACTION NEEDED]\n');
fprintf('  Locate the Bus 8 load block (125 MW / 50 MVAR).\n');
fprintf('  Split into two 62.5 MW / 25 MVAR halves.\n');
fprintf('  Add Three-Phase Breaker in series with one half:\n');
fprintf('    SwitchTimes = [ct]  (already set in PreLoadFcn)\n');
fprintf('    Initial state = closed, transitions to open.\n\n');

%% ---- STEP 5.5: Set synchronous machine initial rotor angles (match RK4 values) ----
% RK4 steady-state for Scenario 2: delta0 = [2.1500, 18.9000, 12.5000] deg
% These values come from pinn_rk4/pinn-scenario-2-final.ipynb and are the
% reference physics parameters for the IEEE 9-bus system.
delta0_rk4_deg = [2.1500, 18.9000, 12.5000];  % [G1, G2, G3] degrees

% mach_blocks already found in Step 3.5 above
if isempty(mach_blocks)
    fprintf('[WARN] No synchronous machine blocks found — initial angles NOT set.\n');
    fprintf('       Open scenario_2.slx and set machine initial angles manually:\n');
    fprintf('       G1 = %.4f deg, G2 = %.4f deg, G3 = %.4f deg\n', delta0_rk4_deg);
else
    fprintf('[OK] Found %d machine block(s). Setting initial rotor angles...\n', numel(mach_blocks));
    % Map each block to its RK4 generator index by MVA rating, NOT alphabetical sort.
    % Standard IEEE 9-bus: G1=247.5 MVA (Bus1), G2=192 MVA (Bus2), G3=128 MVA (Bus3).
    % Alphabetical sort puts 128 MVA first, which would incorrectly assign G1's angle.
    mva_to_gidx = {{'247', 1}, {'192', 2}, {'128', 3}};
    for bi = 1:numel(mach_blocks)
        blk = mach_blocks{bi};
        gi  = 0;
        for mi = 1:numel(mva_to_gidx)
            if contains(blk, mva_to_gidx{mi}{1})
                gi = mva_to_gidx{mi}{2};
                break;
            end
        end
        if gi == 0
            fprintf('  [WARN] Could not identify generator for %s — skipping\n', blk);
            continue;
        end
        angle_deg = delta0_rk4_deg(gi);
        success   = false;
        for param = {'init_IC', 'InitialConditions', 'IC', 'Machine_IC'}
            try
                old = get_param(blk, param{1});
                if isnumeric(old) && numel(old) >= 2
                    old(2) = angle_deg;
                    set_param(blk, param{1}, mat2str(old, 6));
                elseif isnumeric(old) && numel(old) == 1
                    set_param(blk, param{1}, num2str(angle_deg));
                end
                fprintf('  G%d (%s): %s = %.4f deg\n', gi, blk, param{1}, angle_deg);
                success = true;
                break;
            catch
            end
        end
        if ~success
            fprintf('  [WARN] G%d (%s): could not set angle — set manually to %.4f deg\n', ...
                    gi, blk, angle_deg);
        end
    end
end

%% ---- STEP 6: Add "To Workspace" blocks ----
vars = {'delta1_sim','delta2_sim','delta3_sim', ...
        'omega1_sim','omega2_sim','omega3_sim'};

for i = 1:6
    blk_path = [mdl '/' vars{i}];
    if isempty(find_system(mdl, 'Name', vars{i}))
        add_block('simulink/Sinks/To Workspace', blk_path, ...
            'VariableName', vars{i},             ...
            'SaveFormat',   'Timeseries',        ...
            'SampleTime',   '-1',                ...
            'Position', [1050, 60+(i-1)*95, 1150, 90+(i-1)*95]);
        fprintf('[OK] Added To Workspace block: %s\n', vars{i});
    else
        fprintf('[SKIP] Block already exists: %s\n', vars{i});
    end
end

%% ---- STEP 7: Save ----
save_system(mdl);
fprintf('\n[DONE] scenario_2.slx saved.\n');
fprintf('Next steps:\n');
fprintf('  1. Complete the manual Bus 8 load split + breaker (Step 5).\n');
fprintf('  2. Run wire_workspace_blocks.m (set mdl = ''scenario_2'').\n');
fprintf('  3. Run run_simulation.m        (set scenario = 2).\n');
