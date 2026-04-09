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
% PRE-REQUISITE for blocks (one-time, manual):
%   Ensure Mux_rotor_angle, Scope_rotor_angle, and rotor_angle_sim blocks are
%   already wired in the model before running this script.
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

%% ---- STEP 4: (Blocks already configured in model) ----
fprintf('[INFO] Assuming Mux_rotor_angle, Scope, and To Workspace blocks are already in the model.\n');

%% ---- STEP 5: Run simulation ----
fprintf('\nRunning simulation (StopTime = %.1f s)...\n', t_end);
tic;
sim_out = sim(mdl, 'StopTime', num2str(t_end));
fprintf('Simulation finished in %.1f s\n', toc);

%% ---- STEP 7: Extract outputs ----
try
    logged_names = sim_out.who;
    preferred_names = {'Abs', 'delta_abs_sim', 'delta_sim_i', 'delta_all_sim', 'rotor_angle_sim'};
    output_name = '';
    for ni = 1:numel(preferred_names)
        if any(strcmp(logged_names, preferred_names{ni}))
            output_name = preferred_names{ni};
            break;
        end
    end
    if isempty(output_name)
        error('No supported absolute-angle output variable found in SimulationOutput.');
    end

    rotor_angle_ts = sim_out.get(output_name);
    rotor_angle_all = rotor_angle_ts.Data;
    t_sim = rotor_angle_ts.Time;
    fprintf('[OK] Using logged signal: %s\n', output_name);
catch
    error('[ERROR] Cannot find the absolute rotor-angle output. Check the middle scope logging name.');
end
fprintf('Simulink output: %d time steps, t=[%.4f, %.4f] s\n', ...
        length(t_sim), t_sim(1), t_sim(end));

%% ---- STEP 8: Unit conversion ----
% rotor_angle_all is expected to already be absolute rotor angles in radians
% from the middle scope path. Keep a raw copy for reference.
delta_sim_rad = rotor_angle_all;
omega_sim_rads = rotor_angle_all;

%% ---- STEP 9: Interpolate to reference grid ----
% Interpolate both absolute angles and deviations
delta_sim_i = interp1(t_sim, delta_sim_rad,    T_ref, 'linear', 'extrap');
omega_sim_i = interp1(t_sim, omega_sim_rads,   T_ref, 'linear', 'extrap');
fprintf('Interpolated to %d points on T_ref grid (dt=%.4f s)\n', length(T_ref), dt_ref);

%% ---- STEP 10: Initial condition verification ----
% Check initial rotor angles
delta0_sim_deg = rad2deg(delta_sim_i(1, :));
omega0_dev_rad = omega_sim_i(1, :);

fprintf('\n[IC CHECK]\n');
fprintf('  Simulink delta0 (deg):   %8.4f  %8.4f  %8.4f\n', delta0_sim_deg);
fprintf('  Simulink dev0 (rad):     %8.4f  %8.4f  %8.4f\n', omega0_dev_rad);
fprintf('  (Absolute angles should match the notebook and start near the original delta0)\n');

max_dev0 = max(abs(omega0_dev_rad));
if max_dev0 > 0.01
    fprintf('[WARN] Initial values look suspicious; verify the middle scope is absolute rotor angle.\n');
else
    fprintf('[OK] Initial values captured successfully (max |dev0| = %.4f).\n', max_dev0);
end

%% ---- STEP 11: Save .mat file ----
delta0_sim = delta_sim_i(1, :);  % 1x3 rad — initial rotor angles (absolute)
omega0_sim = omega_sim_i(1, :);  % 1x3 rad — initial rotor angle deviations

save(out_file, ...
     'T_ref',           ...  % 4001x1 time vector
     'delta_sim_i',     ...  % 4001x3 rotor angles in radians (absolute) — interpolated
     'omega_sim_i',     ...  % 4001x3 rotor angle deviations (rad) — interpolated
     'delta0_sim',      ...  % 1x3  initial rotor angles (radians, absolute) — for PINN hard IC
     'omega0_sim',      ...  % 1x3  initial rotor angle deviations (rad)    — for PINN hard IC
     't_sim',           ...  % raw Simulink time vector
     'rotor_angle_all');... % raw (uninterpolated) rotor angle deviations in radians from Mux
fprintf('\n[SAVED] %s\n', out_file);

%% ---- STEP 12: Quickcheck plot ----
fig = figure('Name', sprintf('Scenario %d — Rotor Angles', scenario), ...
             'Position', [100, 100, 1000, 600], 'Visible', 'on');
t_event = ct;
colors  = {[0.2 0.4 0.8], [0.8 0.2 0.2], [0.1 0.7 0.3]};

hold on;
for g = 1:3
    plot(T_ref, rad2deg(delta_sim_i(:,g)), 'LineWidth', 2.5, 'Color', colors{g}, ...
         'DisplayName', sprintf('G%d', g));
end
xline(t_event, 'k:', 'LineWidth', 1.5, 'DisplayName', 'Event cleared');
hold off;

ylabel('Rotor Angle (deg)', 'FontSize', 11);
xlabel('Time (s)', 'FontSize', 11);
title(sprintf('Scenario %d — Absolute Rotor Angles of All Generators (t_{event}=%.4f s)', scenario, t_event), ...
      'FontSize', 12, 'FontWeight', 'bold');
legend('Location', 'best', 'FontSize', 10);
grid on;

png_file = sprintf('scenario_%d_simulink_quickcheck.png', scenario);
saveas(fig, png_file);
fprintf('[PLOT] Saved %s\n', png_file);

%% ---- DONE ----
fprintf('\n=== DONE ===\n');
fprintf('Next step: open pinn_simulink/pinn-simulink-scenario-%d.ipynb\n', scenario);
fprintf('           and upload %s to Kaggle dataset.\n', out_file);
