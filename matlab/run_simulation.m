%% =========================================================
% RUN SCRIPT v4 — Run Simulink, save outputs as .mat
% Works for scenario_1 and scenario_2
%
% USAGE: Set scenario = 1 or 2, then Run.
%
% OUTPUT: scenario_N_simulink_outputs.mat
%   T_ref (4001x1), delta_sim_i (4001x3), omega_sim_i (4001x3)
%% =========================================================
clc;   % clear Command Window only — do NOT use 'clear' (it wipes ct)

scenario = 2;   % <-- SET TO 1 OR 2

%% ---- Config ----
mdl        = sprintf('scenario_%d', scenario);
t_event    = 5/60;   % fault clear time (S1) OR load outage time (S2)
t_end      = 2.0;
dt_ref     = 5e-4;
T_ref      = (0 : dt_ref : t_end)';   % 4001×1
out_file   = sprintf('scenario_%d_simulink_outputs.mat', scenario);

%% ---- Set ct in base workspace BEFORE sim() ----
ct = 5/60;
assignin('base', 'ct', ct);
fprintf('[OK] ct = %.5f set in base workspace\n', ct);

%% ---- Load model ----
fprintf('Loading %s...\n', mdl);
load_system(mdl);

%% ---- Disable fault block for Scenario 2 ----
if scenario == 2
    fault_blocks = find_system(mdl, 'RegExp', 'on', 'Name', '.*[Ff]ault.*');
    for fi = 1:length(fault_blocks)
        try
            set_param(fault_blocks{fi}, 'Commented', 'on');
            fprintf('[OK] Disabled: %s\n', fault_blocks{fi});
        catch
        end
    end
end

%% ---- Run simulation ----
fprintf('Running simulation (StopTime = %.1f s)...\n', t_end);
tic;
sim_out = sim(mdl, 'StopTime', num2str(t_end));
fprintf('Simulation finished in %.1f s\n', toc);

%% ---- Extract outputs ----
try
    d1 = sim_out.delta1_sim.Data;  t_sim = sim_out.delta1_sim.Time;
    d2 = sim_out.delta2_sim.Data;
    d3 = sim_out.delta3_sim.Data;
    w1 = sim_out.omega1_sim.Data;
    w2 = sim_out.omega2_sim.Data;
    w3 = sim_out.omega3_sim.Data;
catch
    error('Cannot find To Workspace outputs. Run wire_workspace_blocks.m first.');
end
fprintf('Simulink output: %d time steps\n', length(t_sim));

%% ---- Stack & convert units ----
delta_sim     = [d1, d2, d3];          % degrees
omega_sim     = [w1, w2, w3];          % pu deviation
delta_sim_rad = deg2rad(delta_sim);
omega_s       = 2 * pi * 60;          % 376.99 rad/s
omega_sim_rads= omega_sim * omega_s;

%% ---- Interpolate to T_ref grid ----
delta_sim_i = interp1(t_sim, delta_sim_rad,   T_ref, 'linear', 'extrap');
omega_sim_i = interp1(t_sim, omega_sim_rads,  T_ref, 'linear', 'extrap');
fprintf('Interpolated to %d points (T_ref grid)\n', length(T_ref));

%% ---- Verify initial angles match RK4 values ----
delta0_sim_deg = rad2deg(delta_sim_i(1, :));
if scenario == 1
    delta0_rk4_deg = [2.2717, 19.7315, 13.1752];
else
    delta0_rk4_deg = [2.1500, 18.9000, 12.5000];
end
fprintf('\n[IC CHECK] Simulink delta0 (deg): %.4f  %.4f  %.4f\n', delta0_sim_deg);
fprintf('[IC CHECK] RK4      delta0 (deg): %.4f  %.4f  %.4f\n', delta0_rk4_deg);
fprintf('[IC CHECK] Offset              : %.4f  %.4f  %.4f\n', ...
        delta0_sim_deg - delta0_rk4_deg);
if max(abs(delta0_sim_deg - delta0_rk4_deg)) > 1.0
    fprintf('[WARN] Offset > 1 deg — run setup_scenario_%d.m again to fix machine ICs.\n', scenario);
else
    fprintf('[OK] Initial angles match RK4 values within 1 deg.\n');
end

%% ---- Save ----
% delta0_sim / omega0_sim: t=0 initial state (radians / rad/s).
% Loaded by PINN notebooks to set hard IC encoding and recompute Pm.
delta0_sim = delta_sim_i(1, :);   % 1×3, radians
omega0_sim = omega_sim_i(1, :);   % 1×3, rad/s
save(out_file, 'T_ref', 'delta_sim_i', 'omega_sim_i', ...
               'delta0_sim', 'omega0_sim', ...
               't_sim', 'delta_sim_rad', 'omega_sim_rads');
fprintf('[SAVED] %s\n', out_file);

%% ---- Quick sanity plot ----
fig    = figure('Name', sprintf('Scenario %d — Quick Check', scenario), ...
                'Position', [100 100 1200 700]);
labels = {'\delta_1', '\delta_2', '\delta_3'};
colors = {'b', 'r', 'g'};

for g = 1:3
    subplot(2,3,g);
    plot(T_ref, rad2deg(delta_sim_i(:,g)), 'LineWidth', 1.8, 'Color', colors{g});
    xline(t_event, 'k:', 'LineWidth', 1.5);
    ylabel([labels{g} ' (deg)']); xlabel('Time (s)');
    title(sprintf('G%d Rotor Angle', g)); grid on;

    subplot(2,3,g+3);
    plot(T_ref, omega_sim_i(:,g), 'LineWidth', 1.8, 'Color', colors{g});
    xline(t_event, 'k:', 'LineWidth', 1.5);
    ylabel(['\omega_' num2str(g) ' (rad/s)']); xlabel('Time (s)');
    title(sprintf('G%d Speed Deviation', g)); grid on;
end

sgtitle(sprintf('Scenario %d — Simulink Output Check', scenario), ...
        'FontSize', 13, 'FontWeight', 'bold');
saveas(fig, sprintf('scenario_%d_simulink_quickcheck.png', scenario));
fprintf('[PLOT] Saved scenario_%d_simulink_quickcheck.png\n', scenario);