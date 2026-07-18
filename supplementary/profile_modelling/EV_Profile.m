%% Synthetic EV Dataset Generator (24-hour EVCS)
% Capacity: 40 vehicles
% Charger power: 11 kW

clear; clc; close all;

%% PARAMETERS
station_capacity = 40;
charger_power = 11;        % kW
day_seconds = 24*3600;

% Number of EVs generated (more than capacity because some leave)
num_day_ev   = 50;
num_night_ev = 40;

%% BATTERY CAPACITY DISTRIBUTION (kWh)
battery_options = [40 50 60 80 90];

%% ---------- DAYTIME VEHICLES ----------
% Arrival around morning (centered near 9 AM)

day_arrival = normrnd(9,1,[num_day_ev 1]);
day_arrival(day_arrival<0)=0;
day_arrival(day_arrival>24)=24;

% Parking duration (workplace style)
day_parking = normrnd(7,1,[num_day_ev 1]);
day_parking(day_parking<1)=1;

day_departure = day_arrival + day_parking;
day_departure(day_departure>24)=24;

%% ---------- NIGHT VEHICLES ----------
% Arrival around evening (centered near 19:00)

night_arrival = normrnd(18,1,[num_night_ev 1]);
night_arrival(night_arrival<0)=0;
night_arrival(night_arrival>24)=24;

% Overnight parking
night_parking = normrnd(10,2,[num_night_ev 1]);
night_parking(night_parking<4)=4;

night_departure = night_arrival + night_parking;
night_departure(night_departure>24)=24;

%% ---------- COMBINE VEHICLES ----------

arrival_time = [day_arrival ; night_arrival];
departure_time = [day_departure ; night_departure];

arrival_time = round(arrival_time * 4) / 4;
departure_time = ceil(departure_time * 4) / 4;

departure_time(departure_time > 24) = 24;
departure_time = max(departure_time, arrival_time + 0.25);

num_ev = length(arrival_time);

%% ---------- ARRIVAL SOC ----------
arrival_soc = normrnd(0.35,0.15,[num_ev 1]);
arrival_soc(arrival_soc<0.1)=0.1;
arrival_soc(arrival_soc>0.8)=0.8;

arrival_soc = round(arrival_soc * 100) / 100;

%% ---------- BATTERY CAPACITY ----------
battery_capacity = battery_options(randi(length(battery_options),num_ev,1))';

%% ---------- MAX POSSIBLE SOC ----------
parking_time = departure_time - arrival_time;

energy_possible = charger_power .* parking_time; % kWh

max_soc_possible = arrival_soc + energy_possible./battery_capacity;

max_soc_possible(max_soc_possible>1) = 1;

%% ---------- EXPECTED SOC ----------
expected_soc = arrival_soc + (0.8+0.1*rand(num_ev,1)).*(max_soc_possible-arrival_soc);

% Slightly reduce expected SOC for night arrivals
night_index = arrival_time >= 18;   % vehicles arriving evening/night

reduction_factor = 0.2 + 0.05*rand(sum(night_index),1); % 0.90–0.95

expected_soc(night_index) = arrival_soc(night_index) + ...
    reduction_factor .* (expected_soc(night_index) - arrival_soc(night_index));

expected_soc = round(expected_soc * 20) / 20;

%% ---------- SORT BY ARRIVAL TIME ----------
[arrival_time, idx] = sort(arrival_time);

departure_time = departure_time(idx);
arrival_soc = arrival_soc(idx);
expected_soc = expected_soc(idx);
battery_capacity = battery_capacity(idx);

%% ---------- ENFORCE CAPACITY LIMIT (<=30) ----------
time_vector = 0:0.1:24;
occupancy = zeros(size(time_vector));

valid = true(length(arrival_time),1);

for i=1:length(arrival_time)

    occ_temp = occupancy;
    
    occ_temp(time_vector>=arrival_time(i) & time_vector<=departure_time(i)) = ...
        occ_temp(time_vector>=arrival_time(i) & time_vector<=departure_time(i)) + 1;
    
    if max(occ_temp) <= station_capacity
        occupancy = occ_temp;
    else
        valid(i) = false;
    end

end

arrival_time = arrival_time(valid);
departure_time = departure_time(valid);
arrival_soc = arrival_soc(valid);
expected_soc = expected_soc(valid);
battery_capacity = battery_capacity(valid);

%% ---------- CONVERT TIME TO HH:MM ----------
arrival_hr = floor(arrival_time);
arrival_min = round((arrival_time-arrival_hr)*60);

departure_hr = floor(departure_time);
departure_min = round((departure_time-departure_hr)*60);

arrival_str = strings(length(arrival_time),1);
departure_str = strings(length(arrival_time),1);

for i=1:length(arrival_time)
    arrival_str(i) = sprintf('%02d:%02d',arrival_hr(i),arrival_min(i));
    departure_str(i) = sprintf('%02d:%02d',departure_hr(i),departure_min(i));
end

%% ---------- CREATE DATASET ----------
EV_dataset = table(arrival_str, departure_str, arrival_soc*100, expected_soc*100, battery_capacity);

disp('Synthetic EV Dataset:')
disp(EV_dataset)

%% ---------- OPTIONAL: SAVE DATA ----------
writetable(EV_dataset,'ev_data.csv');

%% ---------- OCCUPANCY CHECK ----------
time_vector = 0:0.1:24;
occupancy = zeros(size(time_vector));

for t=1:length(time_vector)
    occupancy(t)=sum(arrival_time<=time_vector(t) & departure_time>=time_vector(t));
end

figure
plot(time_vector,occupancy,'LineWidth',2)
xlabel('Time (hours)')
ylabel('Number of vehicles in an EV aggregation')
title('EV aggregation Occupancy')
grid on
ylim([0 station_capacity+5])


