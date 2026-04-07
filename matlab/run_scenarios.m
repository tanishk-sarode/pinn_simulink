%% =========================================================
% run_scenarios.m  — Clean simulation + export script (Phase 2)
%
% Replaces all old setup_scenario_*.m / wire_workspace_blocks.m scripts.
%
% USAGE:
%   1. Set scenario = 1 or 2 below.
%   2. Run this script from the folder containing IEEE_9bus_new_wow_mach_9.slx
%
% PRE-REQUISITE (one-time, manual):
%   Open IEEE_9bus_new_wow_mach_9.slx in Simulink and fix G1 (247.5 MVA block):
%     Reactances1 = [0.3614, 0.1505, 0.1505, 0.2399, 0.2399, 0.2399, 0.0832]
%   Then run powergui -> Tools -> Load Flow, accept results, and save the model.
%
% PRE-REQUISITE for Scenario 2 (manual, one-time):
%   After this script creates scenario_2.slx, open it and:
%     - Find the Bus 8 load block (100 MW / 35 MVAR)
%     - Copy it; set each copy to 50 MW / 17.5 MVAR
%     - Insert a Three-Phase Breaker in series with one copy:
%         Initial state: closed, SwitchTimes: [ct], transitions: open
%     - Save scenario_2.slx
%
% OUTPUT FILES:
%   scenario_N_simulink_outputs.mat  (T_ref, delta_sim_i, omega_sim_i,
%                                     delta0_sim, omega0_sim)
%   scenario_N_simulink_quickcheck.png
% =========================================================

clc;  % do NOT use 'clear' — preserves workspace variables

%% ---- USER SETTING ----
scenario = 1;   % <-- SET TO 1 OR 2

%% ---- Config ----
src_mdl  = 'IEEE_9bus_new_wow_mach_9';
mdl      = sprintf('scenario_%d', scenario);
t_end    = 2.0;
dt_ref   = 5e-4;
T_ref    = (0 : dt_ref : t_end)';   % 4001 x 1
out_file = sprintf('scenario_%d_simulink_outputs.mat', scenario);

% NOTE: ct is set AFTER load_system (below) because the model's PreLoadFcn
% may overwrite it when the model loads. Do not move this block above load_system.

fprintf('=== run_scenarios.m | Scenario %d ===\n\n', scenario);

%% ---- STEP 1: Create scenario model from base ----
if exist([mdl '.slx'], 'file')
    fprintf('[INFO] %s.slx already exists — using existing file.\n', mdl);
    fprintf('       Delete it to rebuild from base model.\n\n');
else
    copyfile([src_mdl '.slx'], [mdl '.slx']);
    fprintf('[OK] Copied %s.slx -> %s.slx\n', src_mdl, mdl);
end

load_system(mdl);
fprintf('[OK] Loaded %s\n', mdl);

%% ---- STEP 2: Simulation stop time and PreLoadFcn ----
% Set ct HERE (after load_system) so the model's original PreLoadFcn cannot
% overwrite it. The downloaded base model had ct=1.0830 in its PreLoadFcn;
% we override that now.
ct = 5/60;   % fault/outage clearing time: 5 cycles at 60 Hz = 0.08333 s
assignin('base', 'ct', ct);
set_param(mdl, 'StopTime', num2str(t_end));
set_param(mdl, 'PreLoadFcn', 'ct = 5/60;');
fprintf('[OK] StopTime = %.1f s | PreLoadFcn: ct = 5/60 | ct set to %.5f s\n', t_end, ct);

%% ---- STEP 3: Scenario-specific fault / breaker configuration ----
if scenario == 1
    % Three-phase fault at Bus 7: ON briefly after t=0, cleared at t=ct
    fault_switch_str = sprintf('[%g, %g]', 1/600, ct);
    blocks_to_set = { ...
        [mdl '/Three-Phase Fault'],    'SwitchTimes'; ...
        [mdl '/Three-Phase Breaker'],  'SwitchTimes'; ...
        [mdl '/Three-Phase Breaker1'], 'SwitchTimes'; ...
    };
    for bi = 1:size(blocks_to_set, 1)
        blk   = blocks_to_set{bi, 1};
        param = blocks_to_set{bi, 2};
        try
            set_param(blk, param, fault_switch_str);
            fprintf('[OK] %s  %s = %s\n', blk(length(mdl)+2:end), param, fault_switch_str);
        catch e
            fprintf('[WARN] %s: %s\n', blk(length(mdl)+2:end), e.message);
        end
    end

else  % scenario == 2: load outage — disable fault block, keep breakers
    fault_blocks = find_system(mdl, 'RegExp', 'on', 'Name', '.*[Ff]ault.*');
    n_disabled = 0;
    for fi = 1:length(fault_blocks)
        try
            set_param(fault_blocks{fi}, 'Commented', 'on');
            fprintf('[OK] Disabled: %s\n', fault_blocks{fi}(length(mdl)+2:end));
            n_disabled = n_disabled + 1;
        catch e
            fprintf('[WARN] Could not disable %s: %s\n', ...
                    fault_blocks{fi}(length(mdl)+2:end), e.message);
        end
    end
    if n_disabled == 0
        fprintf('[INFO] No Three-Phase Fault blocks found to disable.\n');
    end
    fprintf('[INFO] Scenario 2: Bus 8 load split + breaker must be wired manually.\n');
    fprintf('       If not done yet, stop here, do the manual step, then re-run.\n\n');
end

%% ---- STEP 4: Locate generator BusSelector blocks and ensure To Workspace blocks ----
% Generators output a bus signal; BusSelector extracts delta (deg) and dw (pu speed dev).
vars_delta = {'delta1_sim', 'delta2_sim', 'delta3_sim'};
vars_omega = {'omega1_sim', 'omega2_sim', 'omega3_sim'};

% Find BusSelector blocks that have both 'delta' and 'dw' in their output signals
all_bs  = find_system(mdl, 'BlockType', 'BusSelector');
gen_bs  = {};
for i = 1:length(all_bs)
    try
        sigs = get_param(all_bs{i}, 'OutputSignals');
        if contains(sigs, 'delta') && contains(sigs, 'dw')
            gen_bs{end+1} = all_bs{i}; %#ok
        end
    catch
    end
end

if length(gen_bs) ~= 3
    fprintf('[ERROR] Expected 3 generator BusSelectors with delta+dw, found %d.\n', length(gen_bs));
    fprintf('        Inspect the model manually to identify the correct blocks.\n');
    bdclose(mdl);
    return;
end

fprintf('\n[OK] Found %d generator BusSelector blocks.\n', length(gen_bs));

% Assign each BusSelector to G1/G2/G3 by OutputSignals heuristic
% G2 has 'Load angle delta'; G3 block name contains '3'; G1 is the remainder
gen_assign = zeros(1, 3);
for k = 1:3
    blk  = gen_bs{k};
    sigs = get_param(blk, 'OutputSignals');
    if contains(sigs, 'Load angle', 'IgnoreCase', true)
        gen_assign(k) = 2;
    elseif contains(blk, '/BusSelector3') || contains(blk, '/Bus Selector3')
        gen_assign(k) = 3;
    else
        gen_assign(k) = 1;
    end
end
% Fallback: if not all unique, assign by position
if length(unique(gen_assign)) ~= 3
    fprintf('[WARN] Generator auto-assignment ambiguous — using positional order 1,2,3.\n');
    gen_assign = [1, 2, 3];
end

fprintf('Generator assignment:\n');
for k = 1:3
    fprintf('  G%d <- %s\n', gen_assign(k), gen_bs{k}(length(mdl)+2:end));
end

% Add To Workspace blocks and wire them
for k = 1:3
    gn    = gen_assign(k);
    dvar  = vars_delta{gn};
    ovar  = vars_omega{gn};
    blk   = gen_bs{k};
    sigs  = strtrim(strsplit(get_param(blk, 'OutputSignals'), ','));
    bname = blk(length(mdl)+2:end);  % strip 'mdl/' prefix

    % Port indices
    dp = find(contains(sigs, 'delta'));
    wp = find(contains(sigs, 'dw'));

    for v = {dvar, ovar}
        vname    = v{1};
        vpath    = [mdl '/' vname];
        if isempty(find_system(mdl, 'Name', vname))
            add_block('simulink/Sinks/To Workspace', vpath, ...
                'VariableName', vname, ...
                'SaveFormat',   'Timeseries', ...
                'SampleTime',   '-1', ...
                'Position',     [1200, 50+(gn-1)*120, 1300, 80+(gn-1)*120]);
            fprintf('[OK] Added To Workspace: %s\n', vname);
        end
    end

    % Wire delta port
    try
        add_line(mdl, [bname '/' num2str(dp)], [dvar '/1'], 'autorouting', 'on');
        fprintf('[OK] Wired G%d delta: port %d -> %s\n', gn, dp, dvar);
    catch e
        if ~contains(e.message, 'already connected')
            fprintf('[WARN] G%d delta wire: %s\n', gn, e.message);
        else
            fprintf('[SKIP] G%d delta already wired.\n', gn);
        end
    end

    % Wire omega port
    try
        add_line(mdl, [bname '/' num2str(wp)], [ovar '/1'], 'autorouting', 'on');
        fprintf('[OK] Wired G%d omega: port %d -> %s\n', gn, wp, ovar);
    catch e
        if ~contains(e.message, 'already connected')
            fprintf('[WARN] G%d omega wire: %s\n', gn, e.message);
        else
            fprintf('[SKIP] G%d omega already wired.\n', gn);
        end
    end
end

%% ---- STEP 5: Save scenario model ----
save_system(mdl);
fprintf('\n[OK] Saved %s.slx\n', mdl);

%% ---- STEP 6: Run simulation ----
fprintf('\nRunning simulation (StopTime = %.1f s)...\n', t_end);
tic;
sim_out = sim(mdl, 'StopTime', num2str(t_end));
fprintf('Simulation finished in %.1f s\n', toc);

%% ---- STEP 7: Extract outputs ----
try
    d1 = sim_out.delta1_sim.Data;  t_sim = sim_out.delta1_sim.Time;
    d2 = sim_out.delta2_sim.Data;
    d3 = sim_out.delta3_sim.Data;
    w1 = sim_out.omega1_sim.Data;
    w2 = sim_out.omega2_sim.Data;
    w3 = sim_out.omega3_sim.Data;
catch
    error('[ERROR] Cannot find To Workspace outputs. Check wiring in Step 4.');
end
fprintf('Simulink output: %d time steps, t=[%.4f, %.4f] s\n', ...
        length(t_sim), t_sim(1), t_sim(end));

%% ---- STEP 8: Unit conversion ----
% delta: degrees -> radians
% omega: per-unit speed deviation -> rad/s  (multiply by omega_s = 2*pi*60)
omega_s       = 2 * pi * 60;             % 376.991 rad/s
delta_sim_rad = deg2rad([d1, d2, d3]);   % N x 3, radians
omega_sim_rads= [w1, w2, w3] * omega_s; % N x 3, rad/s

%% ---- STEP 9: Interpolate to reference grid ----
delta_sim_i = interp1(t_sim, delta_sim_rad,    T_ref, 'linear', 'extrap');
omega_sim_i = interp1(t_sim, omega_sim_rads,   T_ref, 'linear', 'extrap');
fprintf('Interpolated to %d points on T_ref grid (dt=%.4f s)\n', length(T_ref), dt_ref);

%% ---- STEP 10: Initial condition verification ----
% NOTE: This model was downloaded from a MATLAB blog — its rotor angles use a
% different electrical reference frame from the Anderson & Fouad textbook.
% Absolute delta0 values will NOT match textbook values and that is expected.
% What matters: (1) omega0 ≈ 0 (model starts at steady state), (2) fault at ct.
delta0_sim_deg = rad2deg(delta_sim_i(1, :));
omega0_sim_rads = omega_sim_i(1, :);

fprintf('\n[IC CHECK]\n');
fprintf('  Simulink delta0 (deg):  %8.4f  %8.4f  %8.4f\n', delta0_sim_deg);
fprintf('  Simulink omega0 (rad/s):%8.4f  %8.4f  %8.4f\n', omega0_sim_rads);
fprintf('  (omega0 should be ~0 if model starts at steady state)\n');

max_omega0 = max(abs(omega0_sim_rads));
if max_omega0 > 0.5
    fprintf('[WARN] Max |omega0| = %.4f rad/s > 0.5 threshold.\n', max_omega0);
    fprintf('       Model may NOT be at steady state at t=0.\n');
    fprintf('       Check: (1) Load Flow applied AND saved before running this script?\n');
    fprintf('              (2) Was the base model saved after clicking Apply in Load Flow?\n');
else
    fprintf('[OK] omega0 within threshold (max |omega0| = %.4f rad/s) — steady state OK.\n', max_omega0);
end

%% ---- STEP 11: Save .mat file ----
delta0_sim = delta_sim_i(1, :);   % 1x3 radians — initial state for PINN
omega0_sim = omega_sim_i(1, :);   % 1x3 rad/s

save(out_file, ...
     'T_ref',        ...  % 4001x1 time vector
     'delta_sim_i',  ...  % 4001x3 rotor angles (radians)
     'omega_sim_i',  ...  % 4001x3 angular velocity deviations (rad/s)
     'delta0_sim',   ...  % 1x3  initial angles (radians) — for PINN hard IC
     'omega0_sim',   ...  % 1x3  initial omega (rad/s)    — for PINN hard IC
     't_sim',        ...  % raw Simulink time vector
     'delta_sim_rad',...  % raw (uninterpolated) angles in radians
     'omega_sim_rads');   % raw (uninterpolated) omega in rad/s
fprintf('\n[SAVED] %s\n', out_file);

%% ---- STEP 12: Quickcheck plot ----
fig = figure('Name', sprintf('Scenario %d — Simulink Quickcheck', scenario), ...
             'Position', [100, 100, 1300, 700], 'Visible', 'on');
t_event = ct;
labels  = {'\delta_1', '\delta_2', '\delta_3'};
colors  = {[0.2 0.4 0.8], [0.8 0.2 0.2], [0.1 0.7 0.3]};

for g = 1:3
    subplot(2, 3, g);
    plot(T_ref, rad2deg(delta_sim_i(:,g)), 'LineWidth', 2, 'Color', colors{g});
    xline(t_event, 'k:', 'LineWidth', 1.5, 'Label', 'cleared');
    ylabel([labels{g} ' (deg)'], 'FontSize', 10);
    xlabel('Time (s)', 'FontSize', 9);
    title(sprintf('G%d Rotor Angle', g), 'FontWeight', 'bold');
    grid on;

    subplot(2, 3, g+3);
    plot(T_ref, omega_sim_i(:,g), 'LineWidth', 2, 'Color', colors{g});
    xline(t_event, 'k:', 'LineWidth', 1.5);
    ylabel(['\omega_' num2str(g) ' (rad/s)'], 'FontSize', 10);
    xlabel('Time (s)', 'FontSize', 9);
    title(sprintf('G%d Speed Deviation', g), 'FontWeight', 'bold');
    grid on;
end

sgtitle(sprintf('Scenario %d — Simulink Output (t_{event}=%.4f s)', scenario, t_event), ...
        'FontSize', 13, 'FontWeight', 'bold');

png_file = sprintf('scenario_%d_simulink_quickcheck.png', scenario);
saveas(fig, png_file);
fprintf('[PLOT] Saved %s\n', png_file);

%% ---- DONE ----
fprintf('\n=== DONE ===\n');
fprintf('Next step: open pinn_simulink/pinn-simulink-scenario-%d.ipynb\n', scenario);
fprintf('           and upload %s to Kaggle dataset.\n', out_file);
