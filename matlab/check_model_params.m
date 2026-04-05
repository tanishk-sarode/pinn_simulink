%% =========================================================
% DIAGNOSTIC SCRIPT — check_model_params.m
% Extracts machine and network parameters from the base Simulink model
% and compares them against the reference RK4-PINN values.
%
% Run this from the folder containing IEEE_9bus_new_wow_mach_9.slx
% BEFORE running any setup scripts.
% =========================================================
clc;

mdl = 'IEEE_9bus_new_wow_mach_9';
load_system(mdl);
fprintf('Loaded: %s\n\n', mdl);

%% ---- Reference values from RK4-PINN notebooks ----
% Source: pinn_rk4/pinn-scenario-1-final.ipynb
% Generator order: G1 = Machine at Bus 1 (247.5 MVA)
%                  G2 = Machine at Bus 2 (192 MVA)
%                  G3 = Machine at Bus 3 (128 MVA)
RK4.H       = [23.64,  6.40,  3.01];           % inertia (MJ/MVA)
RK4.Pm      = [0.716,  1.63,  0.85];           % mechanical power (pu on machine base)
RK4.E       = [1.0566, 1.0502, 1.0170];        % internal voltage magnitude (pu)
RK4.delta0  = [2.2717, 19.7315, 13.1752];      % S1 steady-state angles (deg)
RK4.MVA     = [247.5,  192.0,  128.0];         % machine ratings (MVA)
RK4.kV      = [16.5,   18.0,   13.8];          % terminal voltage (kV)

fprintf('=== REFERENCE VALUES (RK4-PINN) ===\n');
fprintf('%-6s  %8s  %8s  %8s  %8s  %8s\n', ...
        'Gen', 'MVA', 'kV', 'H (s)', 'Pm (pu)', 'E (pu)');
for i = 1:3
    fprintf('G%-5d  %8.1f  %8.1f  %8.2f  %8.3f  %8.4f\n', ...
            i, RK4.MVA(i), RK4.kV(i), RK4.H(i), RK4.Pm(i), RK4.E(i));
end
fprintf('\n');

%% ---- Find all synchronous machine blocks in the model ----
fprintf('=== MACHINE BLOCKS FOUND IN MODEL ===\n');

mach_blocks = [
    find_system(mdl, 'MaskType', 'Synchronous Machine');
    find_system(mdl, 'MaskType', 'Synchronous Machine (Simplified)');
    find_system(mdl, 'RegExp', 'on', 'MaskType', '.*ynchronous.*achine.*')
];
mach_blocks = unique(mach_blocks);

if isempty(mach_blocks)
    fprintf('[ERROR] No synchronous machine blocks found!\n');
    return;
end

fprintf('Found %d machine block(s).\n\n', numel(mach_blocks));

% Print all parameters for each block
all_params = {'MaskType', 'InitialConditions', 'init_IC', 'Finertia', ...
              'H', 'Rr', 'Xd', 'Xq', 'Pm', 'Vf', 'Speed'};

for bi = 1:numel(mach_blocks)
    blk = mach_blocks{bi};
    fprintf('--- Block %d: %s ---\n', bi, blk);

    % Print all mask parameters
    try
        mp = get_param(blk, 'MaskValues');
        mn = get_param(blk, 'MaskNames');
        for pi = 1:numel(mn)
            fprintf('  %-30s = %s\n', mn{pi}, mp{pi});
        end
    catch
        fprintf('  (could not read mask values)\n');
    end

    % Try specific params
    specific = {'InitialConditions', 'init_IC', 'Finertia', 'H', 'Pm', 'E', ...
                'Vf', 'Speed', 'nomPower', 'nomVoltage', 'nomFreq'};
    for pi = 1:numel(specific)
        try
            val = get_param(blk, specific{pi});
            if ~isempty(val)
                fprintf('  [direct] %-25s = %s\n', specific{pi}, mat2str(val));
            end
        catch
        end
    end
    fprintf('\n');
end

%% ---- Find powergui block (contains system-level settings) ----
fprintf('=== POWERGUI SETTINGS ===\n');
pg_blocks = find_system(mdl, 'BlockType', 'S-Function', 'FunctionName', 'sfun_plsc');
if isempty(pg_blocks)
    pg_blocks = find_system(mdl, 'MaskType', 'Powergui');
end
if isempty(pg_blocks)
    pg_blocks = find_system(mdl, 'RegExp', 'on', 'Name', '.*[Pp]owergui.*');
end
if ~isempty(pg_blocks)
    for pi = 1:numel(pg_blocks)
        fprintf('Found: %s\n', pg_blocks{pi});
        try
            mn = get_param(pg_blocks{pi}, 'MaskNames');
            mv = get_param(pg_blocks{pi}, 'MaskValues');
            for i = 1:numel(mn)
                fprintf('  %-30s = %s\n', mn{i}, mv{i});
            end
        catch
            fprintf('  (could not read powergui params)\n');
        end
    end
else
    fprintf('No powergui block found.\n');
end
fprintf('\n');

%% ---- Try to find bus/load blocks to check network ----
fprintf('=== LOAD BLOCKS (network operating point check) ===\n');
load_blocks = find_system(mdl, 'RegExp', 'on', 'MaskType', '.*[Ll]oad.*');
if isempty(load_blocks)
    load_blocks = find_system(mdl, 'RegExp', 'on', 'Name', '.*[Ll]oad.*');
end
for li = 1:numel(load_blocks)
    blk = load_blocks{li};
    fprintf('Load: %s\n', blk);
    try
        mn = get_param(blk, 'MaskNames');
        mv = get_param(blk, 'MaskValues');
        for pi = 1:numel(mn)
            if ~isempty(mv{pi}) && ~strcmp(mv{pi}, '0')
                fprintf('  %-30s = %s\n', mn{pi}, mv{pi});
            end
        end
    catch
        fprintf('  (could not read load params)\n');
    end
    fprintf('\n');
end

%% ---- Generator ordering check ----
fprintf('=== GENERATOR ORDERING DIAGNOSIS ===\n');
fprintf('Alphabetical sort of machine blocks:\n');
sorted = sort(mach_blocks);
for i = 1:numel(sorted)
    fprintf('  Position %d: %s\n', i, sorted{i});
end
fprintf('\n');
fprintf('Expected mapping (by MVA rating):\n');
fprintf('  247.5 MVA block = G1 (H=23.64, delta0=2.27 deg)\n');
fprintf('  192.0 MVA block = G2 (H=6.40,  delta0=19.73 deg)\n');
fprintf('  128.0 MVA block = G3 (H=3.01,  delta0=13.18 deg)\n');
fprintf('\n');
fprintf('ACTION: Check if the alphabetical ordering above matches\n');
fprintf('        the MVA ordering. If 128 MVA sorts before 247.5 MVA,\n');
fprintf('        then alphabetical sort gives WRONG G1/G3 assignment.\n');
fprintf('\n');

fprintf('=== DONE ===\n');
fprintf('Compare the machine InitialConditions and Finertia/H values\n');
fprintf('against the RK4 reference table printed at the top.\n');
