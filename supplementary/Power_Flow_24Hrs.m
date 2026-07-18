clear
clc

% Read the load profile data from Excel file
Load_profile = readtable('Expected Scaling Factor for PV and Load.xlsx');

% Extract load scaling factor at a time step
time = Load_profile.Time;
house = Load_profile.Domestic_pu;
pv = Load_profile.PV_pu;

% Determine the total number of time steps (15 mins)
T = length(time);

% Preallocate matrix to store bus voltages
Voltage_matrix = zeros(33, T);

for t = 1:T
    h = house(t);
    p = pv(t);
    [Voltage_matrix(:,t)]  = Loadflow_33bus_PV(h,p);
    
end

plot(Voltage_matrix(18,:));

