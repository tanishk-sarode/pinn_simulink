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

%% STEP 7 — Save
save_system(mdl);
fprintf('\n[DONE] scenario_1.slx saved.\n');
fprintf('Next step: run wire_workspace_blocks.m\n');