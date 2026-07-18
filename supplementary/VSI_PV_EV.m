%% Calculate VSI

% Read the load profile data from Excel file
Load_profile = readtable('Expected Scaling Factor for PV and Load.xlsx');

% Extract load scaling factor at a time step
time = Load_profile.Hour;
house = Load_profile.Domestic_pu;
pv = Load_profile.PV_pu;

% Determine the total number of time steps (30 mins)
T = length(time);

LD  = load('linedata33bus.m');

Sbase  = 100;
Vbase  = 11;
Zbase  = (Vbase^2) / Sbase;

LD(:,4:5) = LD(:,4:5) / Zbase;   % Convert to pu

R = LD(:,4)/3;
R = [0; R];
X = LD(:,5)/3;
X = [0; X];

VSI_matrix = zeros(33, T);

for t = 1:T
    
    h = house(t);
    p = pv(t);
    N = [0 0 0 0 0];

    [voltage, load_current, bus_power, line_loss] = Loadflow_33bus_PV_EV(h, p, N);
    
    Vs = zeros(33,1); 
    Pr = real(bus_power) / (1000 * Sbase);
    Qr = imag(bus_power) / (1000 * Sbase);
    
    for bus = 1:33
        if bus == 1
            Vs(1) = voltage(1);        % Slack/source bus
        elseif bus == 19
            Vs(19) = voltage(2);        % Branch connection
        elseif bus == 23
            Vs(23) = voltage(3);        % Branch connection
        elseif bus == 26
            Vs(26) = voltage(6);        % Branch connection
        else
            Vs(bus) = voltage(bus-1);    % Upstream bus
        end
    end
    
    term1 = Vs.^4;
    term2 = 4 * (Pr.*X - Qr.*R).^2;
    term3 = 4 * (Pr.*R + Qr.*X) .* Vs.^2;
    
    VSI = term1 - term2 - term3;
    VSI_matrix(:,t) = VSI;
end

%% Plot VSI
figure;
plot(VSI, '-o', 'LineWidth', 1.5);
xlabel('Bus Number');
ylabel('Voltage Stability Index (VSI)');
title('VSI Profile - Base Case');
xlim([1 33]);
xticks(1:33);
grid on;