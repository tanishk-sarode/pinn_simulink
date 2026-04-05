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

%% ---- STEP 4: Simulation stop time ----
set_param(mdl, 'StopTime', '2.0');
fprintf('[OK] StopTime = 2.0 s\n');

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
