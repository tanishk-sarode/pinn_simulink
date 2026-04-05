%% =========================================================
% SETUP SCRIPT — scenario_1.slx  (v3 — fully automatic)
% Scenario 1: Three-Phase Fault at Bus 7
% Fault clearing time: 5/60 s (~0.0833 s, 5 cycles)
% t_end = 2.0 s | 4001 time points
%
% Run from the folder containing IEEE_9bus_new_wow_mach_9.slx
% =========================================================
clc;

src_model = 'IEEE_9bus_new_wow_mach_9';
mdl       = 'scenario_1';

%% STEP 1 — Copy original model
if ~exist([mdl '.slx'], 'file')
    copyfile([src_model '.slx'], [mdl '.slx']);
    fprintf('[OK] Copied %s.slx -> %s.slx\n', src_model, mdl);
else
    fprintf('[SKIP] %s.slx already exists\n', mdl);
end

%% STEP 2 — Load model
load_system(mdl);
fprintf('[OK] Loaded %s\n', mdl);

%% STEP 3 — PreLoadFcn (kept for reference only; breakers are hardcoded below)
set_param(mdl, 'PreLoadFcn', 'ct = 5/60;');
fprintf('[OK] PreLoadFcn set to: ct = 5/60\n');

%% STEP 3.5 — Fix G1 (247.5 MVA) machine parameters to IEEE 9-bus standard values
% Diagnostic showed G1 has placeholder Reactances1=[31..37], PolePairs=20 (hydro),
% RotorType=Salient-pole. These corrupt the load-flow and admittance matrix used
% by Pe, making dynamics wrong even if initial angles are forced to RK4 values.
%
% Correct values: Anderson & Fouad IEEE 9-bus, machine base (pu on 247.5 MVA, 16.5 kV)
%   [Xd, Xd', Xd'', Xq, Xq', Xq'', Xl] = [0.8958, 0.1198, 0.0969, 0.8645, 0.1198, 0.0969, 0.0521]
%   PolePairs = 1 (steam turbine, 3600 rpm, 60 Hz)
%   RotorType = Round

% Find all synchronous machine blocks (reused by Step 6.5 below)
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
    fprintf('[WARN] G1 (247.5 MVA) block not found — fix machine params manually.\n');
    fprintf('         RotorType = Round, PolePairs = 1\n');
    fprintf('         Reactances1 = [0.8958 0.1198 0.0969 0.8645 0.1198 0.0969 0.0521]\n');
else
    fprintf('[OK] Found G1 block: %s\n', g1_block);
    % 1) Rotor type
    try
        set_param(g1_block, 'RotorType', 'Round');
        fprintf('[OK] G1 RotorType = Round\n');
    catch e1
        try
            set_param(g1_block, 'Rotor_type', 'Round');
            fprintf('[OK] G1 Rotor_type = Round\n');
        catch
            fprintf('[WARN] G1 RotorType: %s\n', e1.message);
        end
    end
    % 2) Pole pairs (steam turbine = 3600 rpm = 1 pair at 60 Hz)
    try
        set_param(g1_block, 'PolePairs', '1');
        fprintf('[OK] G1 PolePairs = 1\n');
    catch e2
        fprintf('[WARN] G1 PolePairs: %s\n', e2.message);
    end
    % 3) Reactances [Xd Xd' Xd'' Xq Xq' Xq'' Xl] — machine base pu
    correct_react = '[0.8958, 0.1198, 0.0969, 0.8645, 0.1198, 0.0969, 0.0521]';
    try
        set_param(g1_block, 'Reactances1', correct_react);
        fprintf('[OK] G1 Reactances1 = %s\n', correct_react);
    catch e3
        fprintf('[WARN] G1 Reactances1: %s\n', e3.message);
    end
end
fprintf('\n');

%% STEP 4 — Stop time
set_param(mdl, 'StopTime', '2.0');
fprintf('[OK] StopTime = 2.0 s\n');

%% STEP 5 — Hardcode SwitchTimes (removes ct dependency at sim time)
% Original: Three-Phase Fault = [1, ct], Breakers = [ct]
% Corrected: fault ON near t=0, cleared at t=5/60
ct_val = 5/60;
try
    set_param([mdl '/Three-Phase Fault'],    'SwitchTimes', '[1/600, 5/60]');
    fprintf('[OK] Three-Phase Fault    SwitchTimes = [1/600, 5/60]\n');
catch e
    fprintf('[WARN] Three-Phase Fault: %s\n', e.message);
end
try
    set_param([mdl '/Three-Phase Breaker'],  'SwitchTimes', '[1/600, 5/60]');
    fprintf('[OK] Three-Phase Breaker  SwitchTimes = [1/600, 5/60]\n');
catch e
    fprintf('[WARN] Three-Phase Breaker: %s\n', e.message);
end
try
    set_param([mdl '/Three-Phase Breaker1'], 'SwitchTimes', '[1/600, 5/60]');
    fprintf('[OK] Three-Phase Breaker1 SwitchTimes = [1/600, 5/60]\n');
catch e
    fprintf('[WARN] Three-Phase Breaker1: %s\n', e.message);
end

%% STEP 6 — Add To Workspace blocks
vars = {'delta1_sim','delta2_sim','delta3_sim', ...
        'omega1_sim','omega2_sim','omega3_sim'};

for i = 1:6
    blk_path = [mdl '/' vars{i}];
    if isempty(find_system(mdl, 'Name', vars{i}))
        add_block('simulink/Sinks/To Workspace', blk_path, ...
            'VariableName', vars{i}, ...
            'SaveFormat',   'Timeseries', ...
            'SampleTime',   '-1', ...
            'Position',     [1050, 60+(i-1)*95, 1150, 90+(i-1)*95]);
        fprintf('[OK] Added To Workspace block: %s\n', vars{i});
    else
        fprintf('[SKIP] Block already exists: %s\n', vars{i});
    end
end

%% STEP 6.5 — Set synchronous machine initial rotor angles (match RK4 values)
% RK4 steady-state for Scenario 1: delta0 = [2.2717, 19.7315, 13.1752] deg
% These values come from pinn_rk4/pinn-scenario-1-final.ipynb and are the
% reference physics parameters for the IEEE 9-bus system.
delta0_rk4_deg = [2.2717, 19.7315, 13.1752];  % [G1, G2, G3] degrees

% mach_blocks already found in Step 3.5 above
if isempty(mach_blocks)
    fprintf('[WARN] No synchronous machine blocks found — initial angles NOT set.\n');
    fprintf('       Open scenario_1.slx and set machine initial angles manually:\n');
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

%% STEP 7 — Save
save_system(mdl);
fprintf('\n[DONE] scenario_1.slx saved.\n');
fprintf('Next step: run wire_workspace_blocks.m\n');