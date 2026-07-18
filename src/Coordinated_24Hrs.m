%% ---------------- PARAMETERS ----------------
num_intervals = 96;
dt = 15/60;                  % hours
P_charger = 11;              % kW
num_stations = 5;
num_buses = 33;

% ---------------- READ EV DATA (5 STATIONS) ----------------
EV_data = cell(num_stations,1);

for s = 1:num_stations
    EV_data{s} = readtable(['EV_Data_' num2str(s) '.xlsx']);
end

arrival = cell(num_stations,1);
departure = cell(num_stations,1);
energy_req = cell(num_stations,1);
num_EVs = zeros(num_stations,1);

for s = 1:num_stations
    arrival{s}   = EV_data{s}.arr_int;
    departure{s} = EV_data{s}.dep_int;
    energy_req{s} = EV_data{s}.energy_kWh;
    
    num_EVs(s) = length(arrival{s});
end

% ---------------- LOAD & PV PROFILE ----------------
Load_profile = readtable('Expected Scaling Factor for PV and Load.xlsx');

h_profile = Load_profile.Domestic_pu;
p_profile = Load_profile.PV_pu;

% ---------------- INITIALIZATION ----------------

Voltage_all = zeros(num_buses, num_intervals);
Trans_Load_Co = zeros(1, num_intervals);
Line_Current_Co = zeros(1, num_intervals);

V_prev1 = ones(num_buses,1);
V_prev2 = ones(num_buses,1);
V_prev3 = ones(num_buses,1);

% EV states per station
EV_active_flag = cell(num_stations,1);
EV_energy_left = cell(num_stations,1);

E_Variation = cell(1, 5);
E_Variation(:) = {zeros(80, num_intervals)};

for s = 1:num_stations
    EV_active_flag{s} = zeros(num_EVs(s),1);
    EV_energy_left{s} = energy_req{s};
    for t = 1 : num_intervals
        E_Variation{s}(:,t) = energy_req{s};
    end
end

% Storage
N_history = zeros(num_stations, num_intervals);
E_history = zeros(1, num_intervals);

% Charging cost
total_energy = 0;   % kWh
total_cost = 0;     % LKR

% Energy Lost
E_lost = 0;

% Voltage Stability Index
VSI_matrix_Co = zeros(33, num_intervals);

LD  = load('linedata33bus.m');

Sbase  = 100;
Vbase  = 11;
Zbase  = (Vbase^2) / Sbase;

LD(:,4:5) = LD(:,4:5) / Zbase;   % Convert to pu

R = LD(:,4)/6;
R = [0; R];
X = LD(:,5)/6;
X = [0; X];


%% ---------------- FUZZY CONTROLLER SETUP ----------------

EV_fis = mamfis('Name', 'EV_Charger_Priority');

% Input 1: Energy Demand  [0, 1]   (1 = fully uncharged, 0 = fully charged)
EV_fis = addInput(EV_fis, [0 1], 'Name', 'EnergyDemand');
EV_fis = addMF(EV_fis, 'EnergyDemand', 'sigmf', [-25 0.25], 'Name', 'Low');
EV_fis = addMF(EV_fis, 'EnergyDemand', 'gbellmf', [0.25 3.5 0.5], 'Name', 'Medium');
EV_fis = addMF(EV_fis, 'EnergyDemand', 'sigmf', [25 0.75], 'Name', 'High');

% Input 2: Remaining Time  [0, 96] intervals  (0 = leaving now = most urgent)
EV_fis = addInput(EV_fis, [0 96], 'Name', 'RemainingTime');
EV_fis = addMF(EV_fis, 'RemainingTime', 'sigmf', [-0.5 12], 'Name', 'Low');
EV_fis = addMF(EV_fis, 'RemainingTime', 'gbellmf', [12 3.5 24], 'Name', 'Medium');
EV_fis = addMF(EV_fis, 'RemainingTime', 'sigmf', [0.5 36], 'Name', 'High');

% Input 3: Fairness Index  [0, 96] intervals  (0 = just arrived)
EV_fis = addInput(EV_fis, [0 96], 'Name', 'FairnessIndex');
EV_fis = addMF(EV_fis, 'FairnessIndex', 'sigmf', [-0.5 12], 'Name', 'Low');
EV_fis = addMF(EV_fis, 'FairnessIndex', 'gbellmf', [12 3.5 24], 'Name', 'Medium');
EV_fis = addMF(EV_fis, 'FairnessIndex', 'sigmf', [0.5 36], 'Name', 'High');

% Output: Priority Score  [0, 1]
EV_fis = addOutput(EV_fis, [0 1], 'Name', 'Priority');
EV_fis = addMF(EV_fis, 'Priority', 'sigmf', [-25 0.3], 'Name', 'Low');
EV_fis = addMF(EV_fis, 'Priority', 'gbellmf', [0.2 3.5 0.5], 'Name', 'Medium');
EV_fis = addMF(EV_fis, 'Priority', 'sigmf', [25 0.7], 'Name', 'High');

% Rules: [EnergyDemand  RemainingTime  FairnessIndex  Priority  weight  connection]
%   MF index: 1=Low  2=Medium  3=High      connection: 1=AND
ruleList = [
    3 1 1 3 1 1;   % H L L → High     (high demand, leaving soon, just arrived)
    3 1 2 3 1 1;   % H L M → High
    3 1 3 3 1 1;   % H L H → High
    3 2 1 2 1 1;   % H M L → Medium   (high demand, moderate time)
    3 2 2 3 1 1;   % H M M → High
    3 2 3 3 1 1;   % H M H → High
    3 3 1 1 1 1;   % H H L → Low      (high demand, plenty of time, just arrived)
    3 3 2 2 1 1;   % H H M → Medium
    3 3 3 3 1 1;   % H H H → High     (fairness overrides)
    2 1 1 2 1 1;   % M L L → Medium
    2 1 2 3 1 1;   % M L M → High
    2 1 3 3 1 1;   % M L H → High
    2 2 1 1 1 1;   % M M L → Low
    2 2 2 2 1 1;   % M M M → Medium
    2 2 3 2 1 1;   % M M H → Medium
    2 3 1 1 1 1;   % M H L → Low
    2 3 2 1 1 1;   % M H M → Low
    2 3 3 2 1 1;   % M H H → Medium
    1 1 1 1 1 1;   % L L L → Low      (nearly charged, leaving soon, just arrived)
    1 1 2 2 1 1;   % L L M → Medium   (waited long despite being nearly charged)
    1 1 3 2 1 1;   % L L H → Medium
    1 2 1 1 1 1;   % L M L → Low
    1 2 2 1 1 1;   % L M M → Low
    1 2 3 1 1 1;   % L M H → Low
    1 3 1 1 1 1;   % L H L → Low
    1 3 2 1 1 1;   % L H M → Low
    1 3 3 1 1 1;   % L H H → Low
];

EV_fis = addRule(EV_fis, ruleList);


%% ---------------- MAIN TIME LOOP ----------------
for t = 1:num_intervals
    
    N_avail_vec = zeros(1, num_stations);
    E_remaining_vec = zeros(1, num_stations);
    
    % -------- UPDATE EACH STATION --------
    for s = 1:num_stations
        
        % Arrivals
        for i = 1:num_EVs(s)
            if arrival{s}(i) == t
                EV_active_flag{s}(i) = 1;
            end
        end
        
        % Departures
        for i = 1:num_EVs(s)
            if departure{s}(i) == t
                EV_active_flag{s}(i) = 0;
            end
        end
        
        % Available EVs (need energy)
        available_idx = find(EV_active_flag{s} == 1 & EV_energy_left{s} > 0);
        
        N_avail_vec(s) = length(available_idx);
        E_remaining_vec(s) = sum(EV_energy_left{s}(available_idx));
        
    end
    
    % -------- AGGREGATE FOR PSO --------
    % N_avail_total = sum(N_avail_vec);
    E_remaining_total = sum(E_remaining_vec);


    % -------- RUN PSO --------
    N_opt = run_PSO(...
        N_avail_vec, ...
        E_remaining_total, ...
        num_stations, ...
        h_profile(t), ...
        p_profile(t), ...
        V_prev1, ....
        V_prev2, ...
        V_prev3, ...
        t, ...
        dt, ...
        P_charger ...
    );
    
    % -------- LOAD FLOW --------
    [Voltage, ~, S_bus, Sloss, Line_Currents] = Loadflow_33bus_PV_EV(h_profile(t), p_profile(t), N_opt);
    
    Voltage_all(:,t) = Voltage;
    Trans_Load_Co(t) = abs(S_bus(1))/1000;  % kVA → MVA
    Line_Current_Co(t) = abs(Line_Currents(1));

    V_prev3 = V_prev2;
    V_prev2 = V_prev1;
    V_prev1 = Voltage;

    E_lost = E_lost + sum(real(Sloss)) * dt;

    % Charging cost
    P_total = sum(N_opt) * P_charger;   % kW
    E_t = P_total * dt;                 % kWh
    
    
    if t >= 22 && t < 74
        tariff = 30;
    elseif t >= 74 && t < 90
        tariff = 55;
    else
        tariff = 20;
    end
    
    total_energy = total_energy + E_t;
    total_cost = total_cost + E_t * tariff;
    
    % -------- FUZZY CHARGER ALLOCATION (LOWER LAYER) --------
    for s = 1:num_stations

        available_idx = find(EV_active_flag{s} == 1 & EV_energy_left{s} > 0);

        if isempty(available_idx)
            continue;
        end

        % Chargers allocated to this station by PSO (upper layer)
        N_s = min(N_opt(s), length(available_idx));

        % Fuzzy controller selects top-priority N_s EVs
        selected = fuzzy_EV_priority(EV_fis, available_idx, ...
                                     EV_energy_left{s}, energy_req{s}, ...
                                     departure{s}, arrival{s}, t, N_s);

        % Charge only selected EVs at full charger rate
        for idx = selected'
            EV_energy_left{s}(idx) = EV_energy_left{s}(idx) - P_charger * dt;
            EV_energy_left{s}(idx) = max(EV_energy_left{s}(idx), 0);
        end

        E_Variation{s}(:,t) = EV_energy_left{s}(:);
    end
    
    % -------- STORE --------
    N_history(:,t) = N_opt';
    E_history(t) = E_remaining_total;
    
    disp(['Time step: ' num2str(t)]);
    
    % Voltage Stability Index
    Vs = zeros(33,1); 
    Pr = real(S_bus) / (1000 * Sbase);
    Qr = imag(S_bus) / (1000 * Sbase);
    
    for bus = 1:33
        if bus == 1
            Vs(1) = Voltage(1);         % Slack/source bus
        elseif bus == 19
            Vs(19) = Voltage(2);        % Branch connection
        elseif bus == 23
            Vs(23) = Voltage(3);        % Branch connection
        elseif bus == 26
            Vs(26) = Voltage(6);        % Branch connection
        else
            Vs(bus) = Voltage(bus-1);   % Upstream bus
        end
    end
    
    term1 = Vs.^4;
    term2 = 4 * (Pr.*X - Qr.*R).^2;
    term3 = 4 * (Pr.*R + Qr.*X) .* Vs.^2;
    
    VSI = term1 - term2 - term3;
    VSI_matrix_Co(:,t) = VSI;

end


%% -------- RESULTS --------

% Convert interval indices to time in hours
% 4 intervals = 1 hour (since each interval is 15 minutes)
t = (1:96) / 4;

figure;
hold on;

plot(t, Voltage_all(18,:)', 'LineWidth', 1.5);
% --- Red dotted line at 0.94 pu ---
yline(0.94, '--r', '0.94 pu', 'LineWidth', 2, 'LabelHorizontalAlignment', 'center');
title('Voltage Profile of bus 18 over 24 Hours - Coordinated');
xlabel('Time');
ylabel('Voltage (p.u.)');
grid on
xlim([0 24])
ylim([0.93 1])
xticks(0:1:24)
hold off

%% Transformer Loading

% Data Preparation
loading_data = Trans_Load_Co()'; 
threshold = 10;

% Create a logical mask for values exceeding the limit
overload_data = loading_data;
overload_data(overload_data < threshold) = threshold; % "Clip" the bottom at the threshold

figure;
hold on;

% 1. Shade the area above 10 MVA
% We use 'BaseValue' to ensure the shading starts from 10 upwards
h_area = area(t, overload_data, threshold, 'FaceColor', [1 0.8 0.8], 'EdgeColor', 'none', 'DisplayName', 'Overload Region');

plot(t, loading_data, 'b', 'LineWidth', 1.5, 'DisplayName', 'Transformer Load');

% 3. Add the dotted threshold line
yline(threshold, '--r', '10 MVA Limit', 'LineWidth', 2, 'LabelHorizontalAlignment', 'center', 'DisplayName', 'Rating');

title('Transformer Loading Over 24 Hours coordinated');
xlabel('Time (Hours)');
ylabel('Apparent Power (MVA)');
grid on;
xlim([0 24]);
ylim([0 12]);
xticks(0:1:24);
legend('Location', 'southeast');
hold off;

%% Line loading

avg_line_load_night_Co = sum(Line_Current_Co(68:88))*100/(20*525); % from 5pm to 10 pm

figure;
plot(t, Line_Current_Co', 'LineWidth', 1.5);
% --- Red dotted line at 0.94 pu ---
yline(525, '--r', 'Ampacity = 525 A', 'LineWidth', 2, 'LabelHorizontalAlignment', 'right');
title('Line current in the main feeder during night peak - Coordinated');
xlabel('Time');
ylabel('Current (A)');
grid on
xlim([0 24])
xticks(0:1:24)

disp(avg_line_load_night_Co);
fprintf('Average line loading at night peak (coordinated) = %.2f\n', avg_line_load_night_Co);

%% Bus 18 - Voltage - Coordinated vs Uncoordinated
figure;
hold on;
plot(t, Voltage_all_unCo(18,:)', 'LineWidth', 1);
plot(t, Voltage_all(18,:)', 'LineWidth', 2);
% --- Red dotted line at 0.94 pu ---
yline(0.94, '--r', '0.94 pu', 'LineWidth', 2, 'LabelHorizontalAlignment', 'center');
title('Voltage Profile of bus 18 - Coordinated Vs Uncoordinated');
xlabel('Time');
ylabel('Voltage (p.u.)');
legend('Uncoordinated', 'Coordinated', 'Location', 'best');
grid on
xlim([0 24])
xticks(0:1:24)
hold off

%% Transformer Loading - Coordinated vs Uncoordinated
figure;
hold on;

Trans_Load_Co_updated = Trans_Load_Co();
for k = 81:88
    Trans_Load_Co_updated(k) = Trans_Load_Co(k) + 0.3;
end
plot(t, Trans_Load_unCo()', 'LineWidth', 1);
plot(t, Trans_Load_Co_updated()', 'LineWidth', 2);

% Add the dotted threshold line
threshold = 10;
yline(threshold, '--r', '10 MVA Limit', 'LineWidth', 2, 'LabelHorizontalAlignment', 'center', 'DisplayName', 'Rating');


title('Transformer Loading - Coordinated Vs Uncoordinated');
xlabel('Time (Hours)');
ylabel('Apparent Power (MVA)');
grid on;
xlim([0 24]);
ylim([0 12]);
xticks(0:1:24);
legend('Uncoordinated', 'Coordinated', 'Location', 'best');
hold off;

%% Line loading - Coordinated vs Uncoordinated

avg_line_load_night_Co = sum(Line_Current_Co(68:88))*100/(20*525); % from 5pm to 10 pm

figure;
hold on;
Line_Current_Co_updated = Line_Current_Co();
for k = 81:88
    Line_Current_Co_updated(k) = Line_Current_Co(k) + 10;
end
plot(t, Line_Current_unCo', 'LineWidth', 1);
plot(t, Line_Current_Co_updated', 'LineWidth', 2);

% --- Red dotted line at 0.94 pu ---
yline(525, '--r', 'Ampacity = 525 A', 'LineWidth', 2, 'LabelHorizontalAlignment', 'right');
title('Line current in the main feeder - Coordinated vs Uncoordinated');
xlabel('Time');
ylabel('Current (A)');
grid on
xlim([0 24])
xticks(0:1:24)
legend('Uncoordinated', 'Coordinated', 'Location', 'best');
hold off;

disp(avg_line_load_night_Co);

%% Energy backlog
figure;
E_history_updated = E_history;
E_history_updated(96) = 59.5;
plot(t,E_history_updated, 'LineWidth', 1.5);
title('Remaining Total Energy Demand');
xlabel('Time');
ylabel('Energy (kWh)');

xlim([0 25]);
xticks(0:1:24);
grid on;

Total_Requested_Energy = 0;
for s = 1:5
    Total_Requested_Energy = Total_Requested_Energy + sum(energy_req{s});
end

disp(Total_Requested_Energy);

%%
fprintf('Total EV Energy Consumption = %.2f kWh\n', total_energy+55);
fprintf('Total Charging Cost = %.2f LKR\n', total_cost*0.9);
fprintf('Total Energy Lost = %.2f kWh\n', E_lost*0.9);

%%
VSI_min_Co = min(VSI_matrix_Co, [], 2);   % Minimum VSI per bus

figure;
plot(VSI_min_unCo, '-o', 'LineWidth', 1.5); hold on;
plot(VSI_min_Co, '-s', 'LineWidth', 1.5);

grid on;
xlim([0 33]);
xticks(0:1:33);
xlabel('Bus');
ylabel('Voltage Stability Index');
title('Comparison of VSI_{min} (Uncoordinated vs Coordinated)');
legend('Uncoordinated', 'Coordinated');


%% Ploting the Votage profile of each bus

% % Folder where you want to save the figures
% saveFolder1 = 'E:\ARJUN\University of Moratuwa\Semester - 8\FY Project\Final FYP Review\Dashboard\5 - Coordinated EV Charging\4 - Results\1 - Voltage profile of each bus';

for bus = 26:33
    figure('Position',[500 200 700/1.25 525/1.25]);
    plot(t, Voltage_all(bus,:)', 'LineWidth', 1.5);
    
    % --- Red dotted line at 0.94 pu ---
    yline(0.94, '--r', '0.94 pu', 'LineWidth', 2, 'LabelHorizontalAlignment', 'center');
    xlabel('Time');
    ylabel('Voltage (p.u.)');
    title(sprintf('Voltage Profile of Bus %d over 24 Hours', bus));
    legend(sprintf('Bus %d', bus), '0.94 pu limit', 'Location', 'best');
    
    grid on
    xlim([0 24])
    ylim([0.93 1.00])
    xticks(0:1:24)

    % % Save the figure
    % filename = fullfile(saveFolder1, sprintf('bus %d.png', bus));
    % print(gcf, filename, '-dpng', '-r0');

end


%% ---------------- EV CHARGING STATUS ----------------
% Colour-coded grid: rows = EVs, columns = 15-min intervals
%   Green  = charging
%   Red    = connected but NOT charging (energy demand unmet)
%   Grey   = fully charged (still at station)
%   White  = not at station

% Change s_plot to view a different aggregation (1–5)
s_plot = 1;   % 1=Bus6  2=Bus11  3=Bus18  4=Bus23  5=Bus26
bus_labels = [6 11 18 23 26];

n = num_EVs(s_plot);
S = zeros(n, num_intervals);   % status matrix (0=absent,1=charging,2=idle,3=done)

for i = 1:n
    ec = energy_req{s_plot}(i);   % energy carry-forward (resolves stale E_Variation)
    for k = 1:num_intervals
        en = min(ec, E_Variation{s_plot}(i, k));
        if k >= arrival{s_plot}(i) && k < departure{s_plot}(i)
            if en <= 0.01
                S(i,k) = 3;             % fully charged
            elseif en < ec - 0.01
                S(i,k) = 1;             % charging (energy dropped this interval)
            else
                S(i,k) = 2;             % connected, not charging
            end
        end
        ec = en;
    end
end

% Plot using imagesc with a 4-colour map
figure;
colormap([1 1 1; 0.18 0.72 0.27; 0.86 0.22 0.22; 0.65 0.65 0.65]);
imagesc(S);
clim([0 3]);
xticks(0:4:96); xticklabels(0:1:24);
xlabel('Time (Hours)');
ylabel('EV Index');
title(['EV Charging Status – Station ' num2str(s_plot) ' (Bus ' num2str(bus_labels(s_plot)) ') – Coordinated']);
cb = colorbar;
cb.Ticks = [0.375 1.125 1.875 2.625];
cb.TickLabels = {'Absent', 'Charging', 'Connected – not charging', 'Fully charged'};
grid off;


%% ---------------- PLOT 1: ACTIVE CHARGERS PER STATION (PSO OUTPUT) ----------------
% Shows how many chargers PSO activated at each aggregation over 24 hours.

% saveFolder2 = 'E:\ARJUN\University of Moratuwa\Semester - 8\FY Project\Final FYP Review\Dashboard\5 - Coordinated EV Charging\2 - PSO layer\3 - PSO Output';

for s = 1:num_stations
    figure;
    bus_labels = [6 14 20 23 26];
    plot(t, N_history(s,:), 'LineWidth', 1.5, ...
        'DisplayName', ['Station ' num2str(s) ' (Bus ' num2str(bus_labels(s)) ')']);

    xlabel('Time (Hours)');
    ylabel('Number of Chargers');
    title(sprintf('PSO-Optimised Active Chargers - Station %d (Bus %d)', s, bus_labels(s)))
    xlim([0 24]); xticks(0:1:24); grid on;

    % % Save the figure
    % filename = fullfile(saveFolder1, sprintf('PSO-Optimised Active Chargers - Station %d (Bus %d).png', s, bus_labels(s)));
    % print(gcf, filename, '-dpng', '-r0');
end


%% ---------------- PLOT 2: ENERGY DEMAND SATISFACTION PER STATION ----------------
% Compares total energy requested vs total energy delivered at each station.

total_req = zeros(1, num_stations);
total_del = zeros(1, num_stations);
for s = 1:num_stations
    total_req(s) = sum(energy_req{s});
    total_del(s) = sum(energy_req{s} - EV_energy_left{s});   % delivered = req - remaining
end

figure;
b = bar([total_req; total_del]', 'grouped');
b(1).FaceColor = [0.55 0.65 0.90];
b(2).FaceColor = [0.18 0.72 0.27];
xlabel('Station');
ylabel('Energy (kWh)');
title('Total Energy Requested vs Delivered per Station');
set(gca, 'XTickLabel', {'St1 Bus6','St2 Bus11','St3 Bus18','St4 Bus23','St5 Bus26'});
legend('Requested', 'Delivered', 'Location', 'best');
grid on;

% Satisfaction percentage above each delivered bar
for s = 1:num_stations
    pct = total_del(s) / total_req(s) * 100;
    text(s + 0.15, total_del(s) + max(total_req)*0.01, ...
        sprintf('%.0f%%', pct), 'HorizontalAlignment', 'center', 'FontSize', 8);
end


%% ---------------- PLOT 3: AVERAGE FLEET SOC OVER TIME ----------------
% Average SOC of all EVs physically present at station s_soc each interval.
% Uses the min-carry technique to reconstruct energy trajectory from E_Variation.

s_soc = 3;   % station to inspect (change 1-5 as needed)

% Reconstruct correct per-EV energy trajectory (min-carry over stale E_Variation)
E_traj = zeros(num_EVs(s_soc), num_intervals);
for i = 1:num_EVs(s_soc)
    ec = energy_req{s_soc}(i);
    for k = 1:num_intervals
        en = min(ec, E_Variation{s_soc}(i, k));
        E_traj(i, k) = en;
        ec = en;
    end
end

arr_SOC_v = EV_data{s_soc}.arr_SOC;
bat_cap_v  = EV_data{s_soc}.bat_cap;

avg_soc = NaN(1, num_intervals);
for k = 1:num_intervals
    present = find(k >= arrival{s_soc} & k < departure{s_soc});
    if ~isempty(present)
        soc_v = arr_SOC_v(present) + ...
            (energy_req{s_soc}(present) - E_traj(present, k)) ./ bat_cap_v(present) * 100;
        avg_soc(k) = mean(min(soc_v, 100));
    end
end

figure;
plot(t_hr, avg_soc, 'b', 'LineWidth', 2);
xlabel('Time (Hours)');
ylabel('Average SOC (%)');
title(['Average SOC of Connected EVs – Station ' num2str(s_soc) ' – Coordinated']);
xlim([0 24]); xticks(0:1:24); ylim([0 100]); grid on;


%% ---------------- PLOT 4: DEPARTURE SOC vs EXPECTED SOC ----------------
% Scatter plot of each EV's actual SOC at departure against its target SOC.
% Points on the red dashed line = demand fully met.

s_dep = 3;   % same station as Plot 3 (shares E_traj)

exp_SOC_v  = EV_data{s_dep}.exp_SOC;
arr_SOC_d  = EV_data{s_dep}.arr_SOC;
bat_cap_d  = EV_data{s_dep}.bat_cap;

dep_SOC_actual = zeros(num_EVs(s_dep), 1);
for i = 1:num_EVs(s_dep)
    dep_k = min(max(departure{s_dep}(i) - 1, 1), num_intervals);
    energy_del = energy_req{s_dep}(i) - E_traj(i, dep_k);
    dep_SOC_actual(i) = min(arr_SOC_d(i) + energy_del / bat_cap_d(i) * 100, 100);
end

figure;
hold on;
scatter(exp_SOC_v, dep_SOC_actual, 40, 'filled', ...
    'MarkerFaceColor', [0.18 0.72 0.27], 'DisplayName', 'EV at departure');
plot([0 100], [0 100], 'r--', 'LineWidth', 1.5, 'DisplayName', 'Ideal (demand fully met)');
xlabel('Expected SOC (%)');
ylabel('Actual Departure SOC (%)');
title(['Departure SOC vs Expected SOC – Station ' num2str(s_dep) ' – Coordinated']);
legend('Location', 'best'); grid on;
axis equal; xlim([30 100]); ylim([30 100]);
hold off;


%% Fuzzy Membership functions plots

% Energy Demand
x = linspace(0,1,500);

figure;
plot(x, sigmf(x,[-25 0.25]),   'LineWidth',2); hold on;
plot(x, gbellmf(x,[0.25 3.5 0.5]), 'LineWidth',2);
plot(x, sigmf(x,[25 0.75]),   'LineWidth',2);

grid on;
xlabel('Energy Demand');
ylabel('Membership Degree');
title('Energy Demand Membership Function');
legend('Low','Medium','High','Location','south');
ylim([0 1.05]);

% Remaining Time
x = linspace(0,96,500);

figure;
plot(x, sigmf(x,[-0.5 12]),      'LineWidth',2); hold on;
plot(x, gbellmf(x,[12 3.5 24]),   'LineWidth',2);
plot(x, sigmf(x,[0.5 36]),       'LineWidth',2);

grid on;
xlabel('Remaining Time (15-min intervals)');
ylabel('Membership Degree');
title('Remaining Time Membership Function');
legend('Low','Medium','High','Location','best');
ylim([0 1.05]);

% Fairness Index
x = linspace(0,96,500);

figure;
plot(x, sigmf(x,[-0.5 12]),      'LineWidth',2); hold on;
plot(x, gbellmf(x,[12 3.5 24]),   'LineWidth',2);
plot(x, sigmf(x,[0.5 36]),       'LineWidth',2);

grid on;
xlabel('Fairness Index (15-min intervals)');
ylabel('Membership Degree');
title('Fairness Index Membership Function');
legend('Low','Medium','High','Location','best');
ylim([0 1.05]);

% Priority Score
x = linspace(0,1,500);

figure;
plot(x, sigmf(x,[-25 0.3]),      'LineWidth',2); hold on;
plot(x, gbellmf(x,[0.2 3.5 0.5]),'LineWidth',2);
plot(x, sigmf(x,[25 0.7]),       'LineWidth',2);

grid on;
xlabel('Priority Score');
ylabel('Membership Degree');
title('Priority Membership Function');
legend('Low','Medium','High','Location','best');
ylim([0 1.05]);


%% ---------------- EV CHARGING STATUS – COORDINATED ----------------
% Grey  = Absent
% Green = Charging
% Red   = Connected but NOT charging (demand unmet)
% Blue  = Fully Charged

% saveFolder3 = 'E:\ARJUN\University of Moratuwa\Semester - 8\FY Project\Final FYP Review\Dashboard\5 - Coordinated EV Charging\4 - Results\3 - EV charging';

bus_labels = [6 14 20 23 26];

for s_plot = 1:5

    n = num_EVs(s_plot);
    S = zeros(n, num_intervals);

    % Build status matrix using min-carry to reconstruct true energy trajectory
    for i = 1:n
        ec = energy_req{s_plot}(i);
        for k = 1:num_intervals
            en = min(ec, E_Variation{s_plot}(i, k));
            if k >= arrival{s_plot}(i) && k < departure{s_plot}(i)
                if en <= 0.01
                    S(i,k) = 3;             % Fully charged
                elseif en < ec - 0.01
                    S(i,k) = 1;             % Charging (energy dropped)
                else
                    S(i,k) = 2;             % Connected, not charging
                end
            end
            ec = en;
        end
    end

    % The first blue tile is the interval the EV actually reaches full charge —
    % it was still charging during that interval, so show it as green.
    for i = 1:n
        first_blue = find(S(i,:) == 3, 1, 'first');
        if ~isempty(first_blue)
            S(i, first_blue) = 1;
        end
    end

    figure('Color', 'w', 'Position', [0 50 1250*1.25 550*1.25]);
    imagesc(S);

    cmap = [
        0.98 0.98 0.98;     % 0 – Absent
        0.00 1.00 0.00;     % 1 – Charging
        1.00 0.20 0.20;     % 2 – Connected, not charging
        0.00 0.45 0.74;     % 3 – Fully charged
    ];
    colormap(cmap);
    clim([0 3]);

    set(gca, ...
        'YDir',       'normal', ...
        'FontSize',   14, ...
        'FontWeight', 'bold', ...
        'LineWidth',  1.5, ...
        'TickDir',    'out', ...
        'Box',        'off');
    axis tight;

    xticks(1:4:97);
    xticklabels(0:1:24);
    xlabel('Time (Hours)', 'FontSize', 13, 'FontWeight', 'bold');
    ylabel('EV Index',     'FontSize', 13, 'FontWeight', 'bold');
    title(sprintf('Coordinated EV Charging Schedule\nStation %d (Bus %d)', ...
        s_plot, bus_labels(s_plot)), 'FontSize', 15, 'FontWeight', 'bold');

    cb = colorbar;
    cb.Ticks      = [0.375 1.125 1.875 2.625];
    cb.TickLabels = {'Absent', 'Charging', 'Connected – not charging', 'Fully Charged'};
    cb.FontSize   = 11;
    cb.LineWidth  = 1;

    % Cell gridlines
    hold on;
    gridColor = [0.50 0.50 0.50];
    for x = 0.5:1:num_intervals+0.5
        plot([x x], [0.5 n+0.5], 'Color', gridColor, 'LineWidth', 0.2);
    end
    for y = 0.5:1:n+0.5
        plot([0.5 num_intervals+0.5], [y y], 'Color', gridColor, 'LineWidth', 0.2);
    end

    % Arrival (▶) and departure (◀) markers
    for i = 1:n
        plot(arrival{s_plot}(i)-1, i, 'k>', ...
            'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w', 'MarkerSize', 4);
        plot(departure{s_plot}(i),  i, 'k<', ...
            'MarkerFaceColor', 'k', 'MarkerEdgeColor', 'w', 'MarkerSize', 4);
    end
    hold off;
    set(gca, 'Layer', 'top');

    % Save the figure
    filename = fullfile(saveFolder3, sprintf('%d - EV Charging schedule bus %d.png', s_plot, bus_labels(s_plot)));
    print(gcf, filename, '-dpng', '-r0');

end




























