% Read data from Excel file into a table
data = readtable('EV_Data_1.xlsx');

% Extract arrival and departure interval columns
% Each value represents a 15-minute interval
arrival = data.arr_int;
departure = data.dep_int;

% Initialize a 96x1 vector (one for each 15-minute interval in a day)
% This will store net change in number of cars
counts = zeros(96,1);

% Loop through all arrivals
% For each arrival interval, increment the count by 1
for i = 1:length(arrival)
    idx = arrival(i);          % interval index (1–96)
    counts(idx) = counts(idx) + 1;
end

% Loop through all departures
% For each departure interval, decrement the count by 1
for i = 1:length(departure)
    idx = departure(i);        % interval index (1–96)
    
    % Avoid subtracting at the last interval (optional logic)
    if idx ~= 96 
        counts(idx) = counts(idx) - 1;
    end
end

% Compute cumulative sum to get number of cars present (occupancy)
% at each interval
cum_counts = cumsum(counts);

% Convert interval indices to time in hours
% 4 intervals = 1 hour (since each interval is 15 minutes)
t = (1:96) / 4;

% Plot occupancy over time
plot(t, cum_counts, 'LineWidth', 1.5)
xlabel('Time (Hours)')
ylabel('Occupancy')
title('Occupancy of Aggregator Over the Day')
grid on
xlim([4 24])          % limit x-axis from 0 to 24 hours
xticks(0:1:24)        % show ticks every hour




