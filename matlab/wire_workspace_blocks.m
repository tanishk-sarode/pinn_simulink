%% =========================================================
% WIRING SCRIPT v2 — Auto-detects BusSelector blocks
% Works even when block names contain line-breaks
% Run AFTER setup_scenario_1.m / setup_scenario_2.m
% =========================================================

mdl = 'scenario_2';  % <-- change to 'scenario_1' for Scenario 1

load_system(mdl);

%% ---- Find BusSelector blocks that have delta + dw outputs ----
all_bs = find_system(mdl, 'BlockType', 'BusSelector');
gen_bs = {};
for i = 1:length(all_bs)
    try
        sigs = get_param(all_bs{i}, 'OutputSignals');
        if contains(sigs, 'delta') && contains(sigs, 'dw')
            gen_bs{end+1} = all_bs{i}; %#ok
        end
    catch
    end
end

fprintf('Found %d generator BusSelector blocks with delta+dw outputs:\n', length(gen_bs));
for i = 1:length(gen_bs)
    fprintf('  [%d] %s\n', i, gen_bs{i});
    fprintf('       Outputs: %s\n', get_param(gen_bs{i}, 'OutputSignals'));
end

if length(gen_bs) ~= 3
    error('Expected 3 generator BusSelectors, found %d. Check model.', length(gen_bs));
end

%% ---- Assign G1/G2/G3 based on OutputSignals content ----
% BusSelector2 outputs start with "Load angle delta" → G2
% BusSelector3/4 output "d_theta" first, then "delta" → G3, G1
delta_vars = {'delta1_sim', 'delta2_sim', 'delta3_sim'};
omega_vars = {'omega1_sim', 'omega2_sim', 'omega3_sim'};

gen_assign = zeros(1,3);   % gen_assign(k) = generator index for gen_bs{k}
for k = 1:3
    blk  = gen_bs{k};
    sigs = get_param(blk, 'OutputSignals');
    if startsWith(strtrim(sigs), 'Load angle')
        gen_assign(k) = 2;   % G2
    else
        if contains(blk, '3')
            gen_assign(k) = 3;
        else
            gen_assign(k) = 1;
        end
    end
end

fprintf('\nGenerator assignment:\n');
for k = 1:3
    fprintf('  G%d <- %s\n', gen_assign(k), gen_bs{k});
end

%% ---- Draw lines ----
for k = 1:3
    blk  = gen_bs{k};
    gn   = gen_assign(k);
    dvar = delta_vars{gn};
    ovar = omega_vars{gn};
    sigs = strsplit(get_param(blk, 'OutputSignals'), ',');
    sigs = strtrim(sigs);

    dp = find(contains(sigs, 'delta'));
    wp = find(contains(sigs, 'dw'));

    bname = strrep(blk, [mdl '/'], '');

    try
        add_line(mdl, [bname '/' num2str(dp)], [dvar '/1'], 'autorouting', 'on');
        fprintf('[OK] G%d: %s/port%d -> %s\n', gn, bname, dp, dvar);
    catch e
        fprintf('[WARN] G%d delta: %s\n', gn, e.message);
    end

    try
        add_line(mdl, [bname '/' num2str(wp)], [ovar '/1'], 'autorouting', 'on');
        fprintf('[OK] G%d: %s/port%d -> %s\n', gn, bname, wp, ovar);
    catch e
        fprintf('[WARN] G%d omega: %s\n', gn, e.message);
    end
end

save_system(mdl);
fprintf('\n[DONE] Wiring complete for %s\n', mdl);
fprintf('Open the model to visually verify connections.\n');
