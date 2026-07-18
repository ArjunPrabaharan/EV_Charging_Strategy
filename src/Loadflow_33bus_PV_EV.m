
function [Voltage, Load_Current, S_bus, Sloss, Iline_mag] = Loadflow_33bus_PV_EV (h, p, N)

%======================================================================================
%  Performs load flow analysis of the IEEE 33-bus radial distribution
%  system using the Backward/Forward Sweep method.

%  The function incorporates photovoltaic (PV) generation at selected
%  buses and evaluates the system voltage profile and power losses.

%  INPUTS:
%    h  → Load scaling factor (multiplies base load demand)
%    p  → PV scaling factor (multiplies installed PV capacity)
%    N  → Number of active chargers in each stations (1*5 matrix)

%  OUTPUT:
%    Voltage       : Bus voltage magnitudes (per unit)
%
%    Load_Current  : Load current magnitude at each bus (per unit)
%
%    S_bus         : Complex power injected at each bus (kVA)
%
%    Sloss         : Complex power loss in each distribution branch (kVA)
%======================================================================================


%  ==============================
%   Load System Data
%  ==============================

LD  = load('linedata33bus.m');     % Line data matrix:
                                   % Column 1 → Branch number
                                   % Column 2 → From bus
                                   % Column 3 → To bus
                                   % Column 4 → Resistance (ohm)
                                   % Column 5 → Reactance (ohm)

BD  = load('loaddata33bus.m');     % Bus load data matrix:
                                   % Column 1 → Bus number
                                   % Column 2 → Active power P (kW)
                                   % Column 3 → Reactive power Q (kVAr)

Sbase  = 100;                      % Base apparent power (MVA)
Vbase  = 11;                       % Base voltage (kV)
Zbase  = (Vbase^2) / Sbase;        % Base impedance (ohms)

% Convert system quantities into per-unit
LD(:,4:5)  = LD(:,4:5) / 6*Zbase;         % Convert R and X to per-unit
BD(:,2:3)  = 2.1*BD(:,2:3) / (1000 * Sbase);  % Convert P and Q (kW, kVAr) to pu


%% ============================
%  EV Charging Stations
%  =============================

bus_EV = [6 11 18 23 26];
P_charger = 11;             % kW per charger

Pev = N * P_charger;        % EV power at stations

for k = 1:length(bus_EV)
    
    bus = bus_EV(k);
    
    % Add EV load to active power column
    BD(bus,2) = BD(bus,2) + Pev(k)/(1000*Sbase);
    
end


%% =============================
%   Initialization
%  =============================

% Complex load power at each bus (pu) multiplied by load scaling factor (h)
Sload  = complex(BD(:,2), BD(:,3)) * h;

V  = ones(size(BD,1), 1);             % Initial voltage guess (1∠0 pu)  for 33 buses
                                      % Slack bus assumed at Bus 1

Z  = complex(LD(:,4), LD(:,5));       % Branch impedance in pu

Iline  = zeros(size(LD,1), 1);        % Initialize branch current vector

Iter  = 2000;                         % Maximum allowed iterations
tol   = 1e-6;                         % Voltage convergence tolerance

%% =============================
%   PV Modeling
%  =============================

PVbus  = [10 17 22 25 32];   % PV bus locations
PVcap  = 1000;                % kW per PV unit

Spv = zeros(size(BD,1),1);   % Initialize PV power vector (size 33)

for k = 1:length(PVbus)
    bus = PVbus(k);
    Spv(bus) = (PVcap / (1000 * Sbase));  % Convert kW to pu
end

% Apply PV scaling factor p
Spv = Spv * p;

% Net complex power (Load - PV)
Snet = Sload - Spv;


%% ====================================
%   Backward / Forward Sweep Load Flow
%  ====================================

for i = 1 : Iter

    V_prev  = V;    % Store voltage from previous iteration

    %  Backward Sweep
    %  --------------------------------------------------------------------
    %  Step 1: Compute load currents using:
    %         S = V * conj(I)  →  I = conj(S / V)

    Iload  = conj(Snet ./ V);

    % Step 2: Accumulate branch currents from leaves to slack bus
    for j = size(LD,1) : -1 : 1
        
        % Find all branches connected to the "to-bus" of branch j
        % c → row indices of connected branches
        % e → column position (2 or 3) indicating match in from/to column
        [c, e] = find(LD(:,2:3) == LD(j,3));
        
        % If only one occurrence → leaf bus (no downstream branches)
        if size(c,1) == 1

            % Branch current equals load current at that bus
            Iline(LD(j,1))  = Iload(LD(j,3));
        
        else
            % For intermediate buses:
            % Branch current = Load current
            %                  + Sum of downstream branch currents
            %                  - Self branch current correction
            
            Iline(LD(j,1))  = Iload(LD(j,3)) ...
                              + sum(Iline(LD(c,1))) ...
                              - Iline(LD(j,1));
        end
    end

    %  Forward Sweep
    %  --------------------------------------------------------------------
    %  Update bus voltages moving from slack bus outward
    %  Using branch voltage drop relation:
    %   V_to = V_from − I_branch * Z_branch

    for j = 1 : size(LD,1)
        
        V(LD(j,3))  = V(LD(j,2)) - Iline(LD(j,1)) * Z(j);
    
    end

    %  Convergence Check
    %  --------------------------------------------------------------------

    % Maximum voltage mismatch
    if max(abs(V - V_prev)) < tol
        % fprintf('Load flow converged in %d iterations\n', i);
        break;
    end

    if i == Iter
        warning('Load flow did not converge');
    end
end

%% =============================
%   Results
%  =============================

Voltage      = abs(V);          % Voltage magnitude at each bus (pu)
Vangle       = angle(V);        % Voltage angle (radians)
Load_Current = abs(Iload);      % Load current magnitude at each bus (pu)


%  Branch Loss Calculation
%  ------------------------------------------------------------------------
%  Branch complex power loss:
%     S_loss = |I|^2 * Z

Iline_mag = abs(Iline);           % Magnitude of branch current (pu)
Sloss = (Iline_mag.^2) .* (Z);    % Complex branch loss (pu)


%  Power Flow at Each Bus
%  ------------------------------------------------------------------------
%  Bus complex power is calculated using:
%     S = V * conj(I)

S_bus = zeros(33,1);            % Initialize complex power vector
for bus = 2:33
    % Power flowing into bus from the previous branch
    S_bus(bus,1) = V(bus,1) * conj(Iline(bus-1,1));
end
% Slack bus power includes branch power plus first branch loss
S_bus(1,1) = S_bus(2,1) + Sloss(1,1);

Sloss = Sloss .* (1000 * Sbase);  % Complex branch loss (kW)
S_bus = S_bus .* (1000 * Sbase);  % Complex power at each bus (kW)

Iline_mag = 1000 * Iline_mag .* (Sbase/(sqrt(3)*Vbase));  % Line currents in A
end











