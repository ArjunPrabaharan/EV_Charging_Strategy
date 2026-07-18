%% PARAMETERS (5 stations)
num_intervals = 96;       % 24h with 15-min resolution
dt = 15/60;               % hours
P_charger = 11;           % kW per EV
num_stations = 5;         % number of aggregations

% -------- READ EV DATA (5 FILES) --------
EV_data = cell(num_stations,1);

arrival   = cell(num_stations,1);
departure = cell(num_stations,1);
SOC_init  = cell(num_stations,1);
SOC_exp  = cell(num_stations,1);
bat_cap   = cell(num_stations,1);
num_EVs   = zeros(num_stations,1);

for s = 1:num_stations
    EV_data{s} = readtable(['EV_Data_' num2str(s) '.xlsx']);
    
    arrival{s}   = EV_data{s}.arr_int;
    departure{s} = EV_data{s}.dep_int;
    SOC_init{s}  = EV_data{s}.arr_SOC;
    SOC_exp{s}   = EV_data{s}.exp_SOC;
    bat_cap{s}   = EV_data{s}.bat_cap;
    
    num_EVs(s) = length(arrival{s});
end

% -------- INITIALIZE SOC MATRICES --------
SOC = cell(num_stations,1);

for s = 1:num_stations
    SOC{s} = zeros(num_EVs(s), num_intervals);
    SOC{s}(:,1) = SOC_init{s};
end

% -------- LOAD PROFILE --------
Load_profile = readtable('Expected Scaling Factor for PV and Load.xlsx');

h_profile = Load_profile.Domestic_pu;
p_profile = Load_profile.PV_pu;

% -------- STORAGE --------
Voltage_all_unCo = zeros(33, num_intervals);
Trans_Load_unCo = zeros(1, num_intervals);
Line_Current_unCo = zeros(1, num_intervals);

% Charging cost
total_energy = 0;   % kWh
total_cost = 0;     % LKR

% Energy Lost
E_lost = 0;

% Voltage Stability Index
VSI_matrix_unCo = zeros(33, num_intervals);

LD  = load('linedata33bus.m');

Sbase  = 100;
Vbase  = 11;
Zbase  = (Vbase^2) / Sbase;

LD(:,4:5) = LD(:,4:5) / Zbase;   % Convert to pu

R = LD(:,4)/6;
R = [0; R];
X = LD(:,5)/6;
X = [0; X];



%% -------- MAIN LOOP --------
for t = 1:num_intervals
    
    N = zeros(1, num_stations);   % chargers per station
    
    % -------- PER STATION PROCESS --------
    for s = 1:num_stations
        
        charging_EV = zeros(num_EVs(s),1);
        
        for i = 1:num_EVs(s)
            
            if t >= arrival{s}(i) && t < departure{s}(i)
                
                if SOC{s}(i,t) < SOC_exp{s}(i,1)   % SOC_exp{s}(i,1) or 100 SOC
                    charging_EV(i) = 1;
                end
            end  
        end
        
        % Number of active EVs at this station
        N(s) = sum(charging_EV);
        
        % -------- SOC UPDATE --------
        if t < num_intervals
            for i = 1:num_EVs(s)
                
                SOC{s}(i,t+1) = SOC{s}(i,t);
                
                if charging_EV(i) == 1
                    SOC{s}(i,t+1) = SOC{s}(i,t) + ...
                        (P_charger * dt / bat_cap{s}(i)) * 100;
                    
                    if SOC{s}(i,t+1) > SOC_exp{s}(i,1)       % SOC_exp{s}(i,1) or 100 SOC
                        SOC{s}(i,t+1) = SOC_exp{s}(i,1) ;    % SOC_exp{s}(i,1) or 100 SOC
                    end
                end
            end
        end
    end

    % -------- ENERGY & COST CALCULATION --------
    P_total = sum(N) * P_charger;   % kW
    E_t = P_total * dt;             % kWh
    
    % hour = (t-1) * dt;
    
    if t >= 22 && t < 74
        tariff = 30;
    elseif t >= 74 && t < 90
        tariff = 55;
    else
        tariff = 20;
    end
    
    total_energy = total_energy + E_t;
    total_cost = total_cost + E_t * tariff;

      
    % -------- LOAD FLOW --------
    h = h_profile(t);
    p = p_profile(t);
    
    [Voltage, Load_Current, S_bus, Sloss, Line_Currents] = Loadflow_33bus_PV_EV(h, p, N);
    
    Voltage_all_unCo(:,t) = Voltage;
    Trans_Load_unCo(t) = abs(S_bus(1))/1000;  % kVA → MVA
    Line_Current_unCo(t) = abs(Line_Currents(1));

    E_lost = E_lost + sum(real(Sloss)) * dt;

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
    VSI_matrix_unCo(:,t) = VSI;
    
end
%% -------- RESULTS --------

% Convert interval indices to time in hours
% 4 intervals = 1 hour (since each interval is 15 minutes)
t = (1:96) / 4;

figure;
hold on;
plot(t, Voltage_all_unCo(5,:)', 'LineWidth', 1.5);
plot(t, Voltage_all_unCo(18,:)', 'LineWidth', 1.5);
% --- Red dotted line at 0.94 pu ---
yline(0.94, '--r', '0.94 pu', 'LineWidth', 2, 'LabelHorizontalAlignment', 'center');
title('Voltage Profile of bus 5 and 18 Over 24 Hours');
xlabel('Time');
ylabel('Voltage (p.u.)');
legend('Bus 5', 'Bus 18', '0.94 pu limit', 'Location', 'best');
grid on
xlim([0 24])
xticks(0:1:24)
hold off

% Data Preparation
loading_data = Trans_Load_unCo()'; 
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

title('Transformer Loading Over 24 Hours');
xlabel('Time (Hours)');
ylabel('Apparent Power (MVA)');
grid on;
xlim([0 24]);
ylim([0 12]);
xticks(0:1:24);
legend('Location', 'southeast');
hold off;

avg_line_load_night = sum(Line_Current_unCo(68:88))*100/(20*525); % from 5pm to 10 pm

figure;
plot(t, Line_Current_unCo', 'LineWidth', 1.5);
% --- Red dotted line at 0.94 pu ---
yline(525, '--r', 'Ampacity = 525 A', 'LineWidth', 2, 'LabelHorizontalAlignment', 'center');
title('Line current in the main feeder during night peak');
xlabel('Time');
ylabel('Current (A)');
grid on
xlim([0 24])
xticks(0:1:24)

fprintf('Average line loading at night peak = %.2f\n', avg_line_load_night);

fprintf('Total EV Energy Consumption = %.2f kWh\n', total_energy);
fprintf('Total Charging Cost = %.2f LKR\n', total_cost);
fprintf('Total Energy Lost = %.2f kWh\n', E_lost);

% Voltage Stability Index
VSI_min_unCo = min(VSI_matrix_unCo, [], 2);   % Minimum VSI per bus

figure;
plot(VSI_min_unCo, '-o', 'LineWidth', 1.5);
grid on;
xlabel('Bus Number');
ylabel('Minimum VSI');
title('Worst-Case Voltage Stability Index per Bus - Uncoordinated');






%% ==========================================================================
%                          Additional Visualizations
%  ==========================================================================


% Ploting the Votage profile of each bus

% Folder where you want to save the figures
% saveFolder1 = 'E:\ARJUN\University of Moratuwa\Semester - 8\FY Project\Final FYP Review\Dashboard\4 - Uncoordinated EV Charging\1 - Voltage profile of 33 buses';

for bus = 26:33
    figure('Position',[500 200 700/1.25 525/1.25]);
    plot(t, Voltage_all_unCo(bus,:)', 'LineWidth', 1.5);
    
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

%% ---------------- ACTIVE CHARGERS PER STATION – UNCOORDINATED ----------------
% Total number of simultaneously charging EVs at each station each interval.

N_history_unCo = zeros(num_stations, num_intervals);
t_hr = (1:96) / 4;

for s = 1:num_stations
    for k = 1:num_intervals
        present = (k >= arrival{s}) & (k < departure{s});
        charging = present & (SOC{s}(:, k) < SOC_exp{s}(:,1) - 0.01);
        N_history_unCo(s, k) = sum(charging);
    end
end

% saveFolder2 = 'E:\ARJUN\University of Moratuwa\Semester - 8\FY Project\Final FYP Review\Dashboard\4 - Uncoordinated EV Charging\3 - EV charging';

for s = 1:num_stations
    figure;
    bus_labels = [6 14 20 23 26];
    plot(t_hr, N_history_unCo(s,:), 'LineWidth', 1.5, ...
        'DisplayName', ['Station ' num2str(s) ' (Bus ' num2str(bus_labels(s)) ')']);

    xlabel('Time (Hours)');
    ylabel('Number of Charging EVs');
    title(sprintf('Uncoordinated Simultaneous Charging EVs - Station %d (Bus %d)',...
        s,bus_labels(s)))
    xlim([0 24]); xticks(0:1:24); grid on;

    % % Save the figure
    % filename = fullfile(saveFolder2, sprintf('No. of EVs Charging - Station %d (Bus %d).png', s, bus_labels(s)));
    % print(gcf, filename, '-dpng', '-r0');
end


%% ---------------- EV CHARGING STATUS – UNCOORDINATED ----------------
% Grey = Absent
% Green = Charging
% Blue  = Fully Charged
% Black > = Arrival
% Black < = Departure

% saveFolder3 = 'E:\ARJUN\University of Moratuwa\Semester - 8\FY Project\Final FYP Review\Dashboard\4 - Uncoordinated EV Charging\3 - EV charging';

for s_plot = 1:5                % Station to visualize
    bus_labels = [6 14 20 23 26];
    n = num_EVs(s_plot);
    S = zeros(n,num_intervals);
    
    % Create status matrix
    for i = 1:n
        for k = 1:num_intervals
            if k >= arrival{s_plot}(i) && k < departure{s_plot}(i)
                if SOC{s_plot}(i,k) >= SOC_exp{s_plot}(i,1) - 0.01
                    S(i,k) = 2;     % Fully charged
                else
                    S(i,k) = 1;     % Charging
                end
            end
        end
    end

    % Make the first blue tile green — the EV was still charging during
    % that interval and reached its target SOC by the end of it.
    for i = 1:n
        first_blue = find(S(i,:) == 2, 1, 'first');
        if ~isempty(first_blue)
            S(i, first_blue) = 1;
        end
    end

    % Plot
    figure('Color','w',...
           'Position',[0 50 1250*1.25 550*1.25]);
    imagesc(S)
    
    % Modern colour palette
    cmap = [
        0.98 0.98 0.98      % Absent - Grey
        0.00 1.00 0.00      % Charging - Green
        0.00 0.00 1.00      % Fully Charged - Blue
    ];
    colormap(cmap)
    clim([0 2])
    
    % Axes formatting
    set(gca,...
        'YDir','normal',...
        'FontSize',14,...
        'FontWeight','bold',...
        'LineWidth',1.5,...
        'TickDir','out',...
        'Box','off')
    axis tight
    
    % Time axis (every 2 hours)
    xticks(1:4:97)
    xticklabels(0:1:24)
    
    xlabel('Time (Hours)','FontSize',13,'FontWeight','bold')
    ylabel('EV Index','FontSize',13,'FontWeight','bold')
    
    title(sprintf('Uncoordinated EV Charging Schedule\nStation %d (Bus %d)',...
        s_plot,bus_labels(s_plot)),...
        'FontSize',15,...
        'FontWeight','bold')
    
    % Colorbar
    cb = colorbar;
    cb.Ticks = [1/3 1 5/3];
    cb.TickLabels = {'Absent','Charging','Fully Charged'};
    cb.FontSize = 11;
    cb.LineWidth = 1;
    
    % Cell gridlines
    hold on
    gridColor = [0.50 0.50 0.50];
    
    % Vertical lines
    for x = 0.5:1:num_intervals+0.5
        plot([x x],[0.5 n+0.5],...
            'Color',gridColor,...
            'LineWidth',0.2)
    end
    
    % Horizontal lines
    for y = 0.5:1:n+0.5
        plot([0.5 num_intervals+0.5],[y y],...
            'Color',gridColor,...
            'LineWidth',0.2)
    end
    
    % Arrival and departure markers
    for i = 1:n
        % Arrival
        plot(arrival{s_plot}(i)-1,i,...
            'k>',...
            'MarkerFaceColor','k',...
            'MarkerEdgeColor','w',...
            'MarkerSize',4)
        % Departure
        plot(departure{s_plot}(i),i,...
            'k<',...
            'MarkerFaceColor','k',...
            'MarkerEdgeColor','w',...
            'MarkerSize',4)
    end
    hold off
    set(gca,'Layer','top')

    % % Save the figure
    % filename = fullfile(saveFolder3, sprintf('%d - EV Charging schedule bus %d.png', s_plot, bus_labels(s_plot)));
    % print(gcf, filename, '-dpng', '-r0');
end



