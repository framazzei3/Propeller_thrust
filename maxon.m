%% =====================================================
%  Propeller characterisation — v4
%  4 configs: L_CCW, L_CW, R_CCW, R_CW; 3 reps each
%
%  Changes w.r.t. v3:
%   - Power is in mW (current data are in mA), variable renamed accordingly
%   - k_f identified per repetition -> dispersion of the gain
%   - Thrust-vs-power fitted with momentum-theory law f = c*P^(2/3)
%     and with a free-exponent law f = c*P^alpha (diagnostic)
%   - Diagnostic on negative thrust values before abs()
%   - Fit coefficients computed once and reused in the export section
%   - Local function moved to end of file (MATLAB requirement)
% =====================================================
clear; clc; close all;

%% --- Parameters -----------------------------------------------------------
SUPPLY_VOLTAGE = 5.0;    % V  (PWM supply)
LEVER_ARM      = 0.075;  % m  (torque bench arm)
G              = 9.81;   % m/s^2
MAIN_FOLDER    = 'data';
VOLTAGES       = 0 : 0.5 : 6;  % 13 steps: 0.0, 0.5, ..., 6.0
N_REPS         = 3;

CONFIGS = {'new_L_CCW', 'new_L_CW', 'new_R_CCW', 'new_R_CW'};
COLORS  = {[0.2 0.5 0.9], ...   % blue    L_CCW
           [0.1 0.7 0.3], ...   % green   L_CW
           [0.9 0.3 0.2], ...   % red     R_CCW
           [0.8 0.5 0.0]};      % orange  R_CW

%% --- Load data ------------------------------------------------------------
allData = struct();

for k = 1:numel(CONFIGS)
    cfg = CONFIGS{k};
    allData.(cfg) = cell(N_REPS, 1);

    for rep = 1:N_REPS
        fullName = sprintf('%s_%d', cfg, rep);
        thrust_g = zeros(numel(VOLTAGES), 1);

        for j = 1:numel(VOLTAGES)
            label    = sprintf('%02d', round(VOLTAGES(j) * 10));
            filePath = fullfile(MAIN_FOLDER, fullName, sprintf('%s_%s.xlsx', fullName, label));

            if ~isfile(filePath)
                warning('File not found: %s', filePath);
                thrust_g(j) = NaN;
                continue;
            end

            raw = readmatrix(filePath, 'Sheet', 'Data', 'Range', 'C20:C5000');
            raw = raw(~isnan(raw));

            if isempty(raw)
                thrust_g(j) = NaN;
            else
                thrust_g(j) = abs(mean(raw));
            end
        end

        % Torque -> force -> grams-force
        thrust_g = (thrust_g / LEVER_ARM) / G * 1000;

        % Remove zero-input offset
        thrust_g = thrust_g - thrust_g(1);

        % Diagnostic: negative values after offset removal indicate sensor
        % drift between zeroing and measurement, not genuine reverse thrust.
        nNeg = sum(thrust_g < -1e-6);
        if nNeg > 0
            fprintf('[check] %s: %d point(s) negative after offset removal (min %.3f g)\n', ...
                    fullName, nNeg, min(thrust_g));
        end
        thrust_g = abs(thrust_g);

        rpmPath    = 'prop_rpm_data.xlsx';
        current_mA = readmatrix(rpmPath, 'Sheet', fullName, 'Range', 'B2:B14');
        rpm        = readmatrix(rpmPath, 'Sheet', fullName, 'Range', 'C2:C14');

        T            = table();
        T.Voltage_V  = VOLTAGES';
        T.PWM_pct    = (VOLTAGES' / SUPPLY_VOLTAGE) * 100;
        T.Current_mA = current_mA;
        T.RPM        = rpm;
        T.Thrust_g   = thrust_g;
        T.Power_mW   = VOLTAGES' .* current_mA;   % V * mA = mW

        allData.(cfg){rep} = T;
    end
end

%% --- Figures --------------------------------------------------------------
lineStyles = {'-', '--', ':'};

hFig(1) = figure('Name', 'Thrust vs PWM');          hold on; grid on; box on;
xlabel('PWM duty cycle (%)'); ylabel('Thrust (g)'); title('Thrust vs PWM (all repetitions)');

hFig(2) = figure('Name', 'Thrust vs Power');        hold on; grid on; box on;
xlabel('Power (mW)');         ylabel('Thrust (g)'); title('Thrust vs Power (all repetitions)');

hFig(3) = figure('Name', 'Thrust vs RPM');          hold on; grid on; box on;
xlabel('RPM');                ylabel('Thrust (g)'); title('Thrust vs RPM (all repetitions)');

hFig(4) = figure('Name', 'Thrust vs PWM - Mean');   hold on; grid on; box on;
xlabel('PWM duty cycle (%)'); ylabel('Thrust (g)'); title('Thrust vs PWM (mean \pm std, k_f D^2 fit)');

hFig(5) = figure('Name', 'Thrust vs Power - Mean'); hold on; grid on; box on;
xlabel('Power (mW)');         ylabel('Thrust (g)'); title('Thrust vs Power (mean \pm std, c P^{2/3} fit)');

hFig(6) = figure('Name', 'Thrust vs RPM - Mean');   hold on; grid on; box on;
xlabel('RPM');                ylabel('Thrust (g)'); title('Thrust vs RPM (mean \pm std, k_T n^2 fit)');

%% --- Main analysis loop ---------------------------------------------------
fitResults = struct();

for k = 1:numel(CONFIGS)
    cfg   = CONFIGS{k};
    color = COLORS{k};

    pwm_mat    = zeros(numel(VOLTAGES), N_REPS);
    thrust_mat = zeros(numel(VOLTAGES), N_REPS);
    power_mat  = zeros(numel(VOLTAGES), N_REPS);
    rpm_mat    = zeros(numel(VOLTAGES), N_REPS);

    for rep = 1:N_REPS
        T     = allData.(cfg){rep};
        label = sprintf('%s rep%d', strrep(cfg, '_', ' '), rep);
        ls    = lineStyles{rep};

        pwm_mat(:,rep)    = T.PWM_pct;
        thrust_mat(:,rep) = T.Thrust_g;
        power_mat(:,rep)  = T.Power_mW;
        rpm_mat(:,rep)    = T.RPM;

        figure(hFig(1));
        plot(T.PWM_pct,  T.Thrust_g, ls, 'Color', color, 'LineWidth', 1.5, 'DisplayName', label);
        figure(hFig(2));
        plot(T.Power_mW, T.Thrust_g, ls, 'Color', color, 'LineWidth', 1.5, 'DisplayName', label);
        figure(hFig(3));
        plot(T.RPM,      T.Thrust_g, ls, 'Color', color, 'LineWidth', 1.5, 'DisplayName', label);
    end

    thrust_mean = mean(thrust_mat, 2);
    thrust_std  = std(thrust_mat,  0, 2);
    pwm_mean    = mean(pwm_mat,    2);
    power_mean  = mean(power_mat,  2);
    rpm_mean    = mean(rpm_mat,    2);
    label_mean  = strrep(cfg, '_', ' ');

    valid  = ~isnan(thrust_mean);
    D_mean = pwm_mean / 100;
    f      = thrust_mean(valid);
    SS_tot = sum((f - mean(f)).^2);

    % -----------------------------------------------------------------------
    %  THRUST vs DUTY CYCLE
    %  Model used in the thesis: pure quadratic through the origin f = k_f D^2
    %  General quadratic retained as a diagnostic only (not reported)
    % -----------------------------------------------------------------------
    p2 = polyfit(pwm_mean(valid), thrust_mean(valid), 2);   % [a, b, c] in PWM_pct

    D2 = D_mean(valid).^2;
    kf = (D2' * f) / (D2' * D2);

    thrust_pred_gen  = polyval(p2, pwm_mean(valid));
    thrust_pred_pure = kf * D_mean(valid).^2;
    R2_gen  = 1 - sum((f - thrust_pred_gen).^2)  / SS_tot;
    R2_pure = 1 - sum((f - thrust_pred_pure).^2) / SS_tot;

    % --- k_f identified independently on each repetition -------------------
    kf_reps = zeros(N_REPS, 1);
    for rep = 1:N_REPS
        Trep = allData.(cfg){rep};
        Drep = Trep.PWM_pct / 100;
        vr   = ~isnan(Trep.Thrust_g);
        D2r  = Drep(vr).^2;
        kf_reps(rep) = (D2r' * Trep.Thrust_g(vr)) / (D2r' * D2r);
    end

    % -----------------------------------------------------------------------
    %  THRUST vs ELECTRICAL POWER
    %  Momentum theory: f = k_T w^2 and P_aero = k_Q w^3  =>  f ~ P^(2/3)
    %  A free exponent is also identified, since the measured power is
    %  electrical and includes no-load and resistive losses.
    % -----------------------------------------------------------------------
    valid_p = valid & ~isnan(power_mean) & power_mean > 0;
    P_v = power_mean(valid_p);
    f_p = thrust_mean(valid_p);
    SS_tot_p = sum((f_p - mean(f_p)).^2);

    X23   = P_v.^(2/3);
    c23   = (X23' * f_p) / (X23' * X23);
    R2_23 = 1 - sum((f_p - c23 * X23).^2) / SS_tot_p;

    pl      = polyfit(log(P_v), log(f_p), 1);
    alpha   = pl(1);
    c_free  = exp(pl(2));
    R2_free = 1 - sum((f_p - c_free * P_v.^alpha).^2) / SS_tot_p;

    % -----------------------------------------------------------------------
    %  THRUST vs RPM
    %  f = k_T n^2 with n in RPM (k_T therefore in g/RPM^2)
    % -----------------------------------------------------------------------
    valid_r = valid & ~isnan(rpm_mean);
    n_v     = rpm_mean(valid_r);
    f_r     = thrust_mean(valid_r);
    n2      = n_v.^2;
    kT      = (n2' * f_r) / (n2' * n2);
    R2_kT   = 1 - sum((f_r - kT * n2).^2) / sum((f_r - mean(f_r)).^2);

    % --- Store -------------------------------------------------------------
    fitResults.(cfg).p2       = p2;
    fitResults.(cfg).kf       = kf;
    fitResults.(cfg).kf_reps  = kf_reps;
    fitResults.(cfg).kf_std   = std(kf_reps);
    fitResults.(cfg).kf_mreps = mean(kf_reps);
    fitResults.(cfg).R2_gen   = R2_gen;
    fitResults.(cfg).R2_pure  = R2_pure;
    fitResults.(cfg).c23      = c23;
    fitResults.(cfg).R2_23    = R2_23;
    fitResults.(cfg).alpha    = alpha;
    fitResults.(cfg).c_free   = c_free;
    fitResults.(cfg).R2_free  = R2_free;
    fitResults.(cfg).kT       = kT;
    fitResults.(cfg).R2_kT    = R2_kT;

    % --- Figure 4: Thrust vs PWM (mean) ------------------------------------
    pwm_fine = linspace(0, max(pwm_mean), 300)';
    D_fine   = pwm_fine / 100;

    figure(hFig(4));
    fill([pwm_mean; flipud(pwm_mean)], ...
         [thrust_mean+thrust_std; flipud(thrust_mean-thrust_std)], ...
         color, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    plot(pwm_mean, thrust_mean, 'o', 'Color', color, ...
         'MarkerFaceColor', color, 'MarkerSize', 4, 'DisplayName', label_mean);
    plot(pwm_fine, kf * D_fine.^2, '-', 'Color', color*0.6, ...
         'LineWidth', 1.5, 'DisplayName', sprintf('%s fit (k_f D^2)', label_mean));

    % --- Figure 5: Thrust vs Power (mean) ----------------------------------
    pwr_fine = linspace(0, max(power_mean), 300)';

    figure(hFig(5));
    fill([power_mean; flipud(power_mean)], ...
         [thrust_mean+thrust_std; flipud(thrust_mean-thrust_std)], ...
         color, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    plot(power_mean, thrust_mean, 'o', 'Color', color, ...
         'MarkerFaceColor', color, 'MarkerSize', 4, 'DisplayName', label_mean);
    plot(pwr_fine, c23 * pwr_fine.^(2/3), '-', 'Color', color*0.6, ...
         'LineWidth', 1.5, 'DisplayName', sprintf('%s fit (c P^{2/3})', label_mean));
    plot(pwr_fine, c_free * pwr_fine.^alpha, ':', 'Color', color*0.75, ...
         'LineWidth', 1.5, 'DisplayName', sprintf('%s fit (c P^{%.2f})', label_mean, alpha));

    % --- Figure 6: Thrust vs RPM (mean) ------------------------------------
    rpm_fine = linspace(0, max(rpm_mean), 300)';

    figure(hFig(6));
    fill([rpm_mean; flipud(rpm_mean)], ...
         [thrust_mean+thrust_std; flipud(thrust_mean-thrust_std)], ...
         color, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    plot(rpm_mean, thrust_mean, 'o', 'Color', color, ...
         'MarkerFaceColor', color, 'MarkerSize', 4, 'DisplayName', label_mean);
    plot(rpm_fine, kT * rpm_fine.^2, '-', 'Color', color*0.6, ...
         'LineWidth', 1.5, 'DisplayName', sprintf('%s fit (k_T n^2)', label_mean));
end

for kk = 1:6
    figure(hFig(kk)); legend('show', 'Location', 'northwest');
end

%% --- Max thrust per configuration -----------------------------------------
fprintf('\n=== Max thrust per config (at %.1f V = %d%% PWM) ===\n', ...
        max(VOLTAGES), round(max(VOLTAGES)/SUPPLY_VOLTAGE*100));
fprintf('%-22s %10s %11s %8s\n', 'Config', 'Thrust (g)', 'Power (mW)', 'RPM');
fprintf('%s\n', repmat('-', 1, 55));

for k = 1:numel(CONFIGS)
    cfg = CONFIGS{k};
    for rep = 1:N_REPS
        T = allData.(cfg){rep};
        fprintf('%-22s %10.2f %11.1f %8.0f\n', ...
            sprintf('%s_rep%d', cfg, rep), ...
            T.Thrust_g(end), T.Power_mW(end), T.RPM(end));
    end
end

%% --- Duty-cycle fit summary ----------------------------------------------
fprintf('\n=== Thrust gain (f = k_f D^2, D over the full tested range) ===\n');
fprintf('%-22s %10s %10s %10s %10s %10s\n', ...
        'Config', 'k_f (g)', 'std (g)', 'mean reps', 'R2 pure', 'R2 gen');
fprintf('%s\n', repmat('-', 1, 76));

for k = 1:numel(CONFIGS)
    cfg = CONFIGS{k};
    fr  = fitResults.(cfg);
    fprintf('%-22s %10.3f %10.3f %10.3f %10.4f %10.4f\n', ...
            cfg, fr.kf, fr.kf_std, fr.kf_mreps, fr.R2_pure, fr.R2_gen);
end

fprintf('\n  per-repetition k_f values:\n');
for k = 1:numel(CONFIGS)
    cfg = CONFIGS{k};
    fprintf('  %-22s', cfg);
    fprintf(' %8.3f', fitResults.(cfg).kf_reps);
    fprintf('\n');
end

%% --- Power-law fit summary ------------------------------------------------
fprintf('\n=== Thrust vs electrical power ===\n');
fprintf('%-22s %12s %10s %10s %10s\n', ...
        'Config', 'c (2/3 law)', 'R2 (2/3)', 'alpha', 'R2 (free)');
fprintf('%s\n', repmat('-', 1, 68));

for k = 1:numel(CONFIGS)
    cfg = CONFIGS{k};
    fr  = fitResults.(cfg);
    fprintf('%-22s %12.4f %10.4f %10.3f %10.4f\n', ...
            cfg, fr.c23, fr.R2_23, fr.alpha, fr.R2_free);
end

%% --- RPM fit summary ------------------------------------------------------
fprintf('\n=== Thrust vs RPM (f = k_T n^2, n in RPM) ===\n');
fprintf('%-22s %14s %10s\n', 'Config', 'k_T (g/RPM^2)', 'R2');
fprintf('%s\n', repmat('-', 1, 50));

for k = 1:numel(CONFIGS)
    cfg = CONFIGS{k};
    fr  = fitResults.(cfg);
    fprintf('%-22s %14.3e %10.4f\n', cfg, fr.kT, fr.R2_kT);
end

%% --- Efficiency analysis --------------------------------------------------
fprintf('\n=== Efficiency at 5 V (100%% PWM) ===\n');
fprintf('%-22s %12s %11s %12s\n', 'Config', 'Thrust (g)', 'Power (mW)', 'Eff (g/W)');
fprintf('%s\n', repmat('-', 1, 60));

[~, idx5V] = min(abs(VOLTAGES - 5.0));

for k = 1:numel(CONFIGS)
    cfg = CONFIGS{k};
    thrust_all = zeros(N_REPS, 1);
    power_all  = zeros(N_REPS, 1);
    for rep = 1:N_REPS
        T = allData.(cfg){rep};
        thrust_all(rep) = abs(T.Thrust_g(idx5V));
        power_all(rep)  = T.Power_mW(idx5V);
    end
    t_mean = mean(thrust_all);
    t_std  = std(thrust_all);
    p_mean = mean(power_all);
    eff    = t_mean / p_mean * 1000;   % g/mW -> g/W
    fprintf('%-22s %7.2f+-%-4.2f %11.1f %12.2f\n', cfg, t_mean, t_std, p_mean, eff);
end

%% --- Forward vs backward asymmetry ----------------------------------------
fprintf('\n=== Matched vs mismatched thrust asymmetry ===\n');
fwd_configs = {'new_L_CCW', 'new_R_CW'};
bwd_configs = {'new_L_CW',  'new_R_CCW'};

fwd_thrust = []; bwd_thrust = [];
for k = 1:numel(fwd_configs)
    for rep = 1:N_REPS
        T = allData.(fwd_configs{k}){rep};
        fwd_thrust(end+1) = abs(T.Thrust_g(idx5V)); %#ok<SAGROW>
    end
end
for k = 1:numel(bwd_configs)
    for rep = 1:N_REPS
        T = allData.(bwd_configs{k}){rep};
        bwd_thrust(end+1) = abs(T.Thrust_g(idx5V)); %#ok<SAGROW>
    end
end

fprintf('Matched thrust @ 5V:    %.2f +- %.2f g\n', mean(fwd_thrust), std(fwd_thrust));
fprintf('Mismatched thrust @ 5V: %.2f +- %.2f g\n', mean(bwd_thrust), std(bwd_thrust));
fprintf('Asymmetry ratio:        %.2fx\n', mean(fwd_thrust)/mean(bwd_thrust));

% Asymmetry expressed on the identified gains
kf_fwd = [fitResults.new_L_CCW.kf, fitResults.new_R_CW.kf];
kf_bwd = [fitResults.new_L_CW.kf,  fitResults.new_R_CCW.kf];
fprintf('k_f+ (matched):         %.2f +- %.2f g\n', mean(kf_fwd), std(kf_fwd));
fprintf('k_f- (mismatched):      %.2f +- %.2f g\n', mean(kf_bwd), std(kf_bwd));
fprintf('Gain ratio:             %.2fx\n', mean(kf_fwd)/mean(kf_bwd));

%% --- Export data for pgfplots ---------------------------------------------
exportDir = 'tikz_data';
if ~exist(exportDir, 'dir'), mkdir(exportDir); end

nV   = numel(VOLTAGES);
nCfg = numel(CONFIGS);
tags = {'LCCW','LCW','RCCW','RCW'};

PWM_all       = zeros(nV, nCfg);
Power_all     = zeros(nV, nCfg);
RPM_all       = zeros(nV, nCfg);
Tmean_all     = zeros(nV, nCfg);
Tstd_all      = zeros(nV, nCfg);
Tfit_gen_all  = zeros(nV, nCfg);
Tfit_pure_all = zeros(nV, nCfg);
Tfit_p23_all  = zeros(nV, nCfg);
Tfit_pfree_all= zeros(nV, nCfg);
Tfit_rpm_all  = zeros(nV, nCfg);

PWM_reps    = zeros(nV, nCfg, N_REPS);
Power_reps  = zeros(nV, nCfg, N_REPS);
RPM_reps    = zeros(nV, nCfg, N_REPS);
Thrust_reps = zeros(nV, nCfg, N_REPS);

for k = 1:nCfg
    cfg = CONFIGS{k};
    fr  = fitResults.(cfg);

    pwm_mat    = zeros(nV, N_REPS);
    thrust_mat = zeros(nV, N_REPS);
    power_mat  = zeros(nV, N_REPS);
    rpm_mat    = zeros(nV, N_REPS);

    for rep = 1:N_REPS
        T = allData.(cfg){rep};
        pwm_mat(:,rep)    = T.PWM_pct;
        thrust_mat(:,rep) = T.Thrust_g;
        power_mat(:,rep)  = T.Power_mW;
        rpm_mat(:,rep)    = T.RPM;
    end

    thrust_mean = mean(thrust_mat, 2);
    thrust_std  = std(thrust_mat,  0, 2);
    pwm_mean    = mean(pwm_mat,    2);
    power_mean  = mean(power_mat,  2);
    rpm_mean    = mean(rpm_mat,    2);

    PWM_all(:,k)        = pwm_mean;
    Power_all(:,k)      = power_mean;
    RPM_all(:,k)        = rpm_mean;
    Tmean_all(:,k)      = thrust_mean;
    Tstd_all(:,k)       = thrust_std;
    Tfit_gen_all(:,k)   = polyval(fr.p2, pwm_mean);
    Tfit_pure_all(:,k)  = fr.kf * (pwm_mean/100).^2;
    Tfit_p23_all(:,k)   = fr.c23    * max(power_mean, 0).^(2/3);
    Tfit_pfree_all(:,k) = fr.c_free * max(power_mean, 0).^fr.alpha;
    Tfit_rpm_all(:,k)   = fr.kT * rpm_mean.^2;

    PWM_reps(:,k,:)    = pwm_mat;
    Power_reps(:,k,:)  = power_mat;
    RPM_reps(:,k,:)    = rpm_mat;
    Thrust_reps(:,k,:) = thrust_mat;
end

%% --- thrust_vs_pwm.dat ----------------------------------------------------
varNames = [ colnames('PWM_',    tags), ...
             colnames('Tmean_',  tags), ...
             colnames('Tstd_',   tags), ...
             colnames('Fgen_',   tags), ...
             colnames('Fpure_',  tags), ...
             colnames('PWM_r1_', tags), colnames('Thr_r1_', tags), ...
             colnames('PWM_r2_', tags), colnames('Thr_r2_', tags), ...
             colnames('PWM_r3_', tags), colnames('Thr_r3_', tags) ];

T4 = array2table([ PWM_all, Tmean_all, Tstd_all, Tfit_gen_all, Tfit_pure_all, ...
                   PWM_reps(:,:,1), Thrust_reps(:,:,1), ...
                   PWM_reps(:,:,2), Thrust_reps(:,:,2), ...
                   PWM_reps(:,:,3), Thrust_reps(:,:,3) ], ...
                 'VariableNames', varNames);
writetable(T4, fullfile(exportDir, 'thrust_vs_pwm.dat'), 'Delimiter', ' ');

%% --- thrust_vs_power.dat --------------------------------------------------
%  Pwr_* columns are in mW.
varNames = [ colnames('Pwr_',    tags), ...
             colnames('Tmean_',  tags), ...
             colnames('Tstd_',   tags), ...
             colnames('Fp23_',   tags), ...
             colnames('Fpfree_', tags), ...
             colnames('Pwr_r1_', tags), colnames('Thr_r1_', tags), ...
             colnames('Pwr_r2_', tags), colnames('Thr_r2_', tags), ...
             colnames('Pwr_r3_', tags), colnames('Thr_r3_', tags) ];

T5 = array2table([ Power_all, Tmean_all, Tstd_all, Tfit_p23_all, Tfit_pfree_all, ...
                   Power_reps(:,:,1), Thrust_reps(:,:,1), ...
                   Power_reps(:,:,2), Thrust_reps(:,:,2), ...
                   Power_reps(:,:,3), Thrust_reps(:,:,3) ], ...
                 'VariableNames', varNames);
writetable(T5, fullfile(exportDir, 'thrust_vs_power.dat'), 'Delimiter', ' ');

%% --- thrust_vs_rpm.dat ----------------------------------------------------
varNames = [ colnames('RPM_',    tags), ...
             colnames('Tmean_',  tags), ...
             colnames('Tstd_',   tags), ...
             colnames('FkT_',    tags), ...
             colnames('RPM_r1_', tags), colnames('Thr_r1_', tags), ...
             colnames('RPM_r2_', tags), colnames('Thr_r2_', tags), ...
             colnames('RPM_r3_', tags), colnames('Thr_r3_', tags) ];

T6 = array2table([ RPM_all, Tmean_all, Tstd_all, Tfit_rpm_all, ...
                   RPM_reps(:,:,1), Thrust_reps(:,:,1), ...
                   RPM_reps(:,:,2), Thrust_reps(:,:,2), ...
                   RPM_reps(:,:,3), Thrust_reps(:,:,3) ], ...
                 'VariableNames', varNames);
writetable(T6, fullfile(exportDir, 'thrust_vs_rpm.dat'), 'Delimiter', ' ');

fprintf('\nExported .dat files to ./%s\n', exportDir);

%% --- Local functions (must be at the end of the script) -------------------
function names = colnames(prefix, tags)
    names = strcat(prefix, tags);
end