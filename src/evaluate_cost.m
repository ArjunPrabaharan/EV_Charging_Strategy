function J = evaluate_cost(N_candidate, h, p_pv, V_prev1, E_remaining_total, V_prev2, V_prev3, t, dt, P_charger)

% ---------------- PARAMETERS ----------------

Vmin = 0.94;
Vmax = 1.06;
Trans_limit = 10;   % MVA transformer rating

% Weights (tune if needed)
w1 = 1e9;   % voltage violation
w2 = 1e6;   % voltage fluctuation
w3 = 1e-3;     % Energy backlog
w4 = 1e6;   % transformer overload    

% ---------------- LOAD FLOW ----------------

[Voltage, ~, S_bus, ~, ~] = Loadflow_33bus_PV_EV(h, p_pv, N_candidate);

% ---------------- OBJECTIVE TERMS ----------------

%% J1 — VOLTAGE VIOLATION (STRICT)

over  = max(Voltage - Vmax, 0);
under = max(Vmin - Voltage, 0);

% J1 = sum(over.^2 + under.^2);
J1 = sum(over + under);

%% J2 — VOLTAGE FLUCTUATION AT BUS 18 (ROLLING MEAN SMOOTHING)
% Penalises deviation of current bus-18 voltage from the 3-interval
% rolling mean of the previous three voltages.  This damps oscillations
% caused by PV intermittency without needing a fixed time-window gate.

V18_roll = (V_prev1(18) + V_prev2(18) + V_prev3(18)) / 3;
if t >= 30 && t <= 60
    J2 = 1000*(Voltage(18) - V18_roll)^2;
else
    J2 = 0;
end

%% J3 — ENERGY BACKLOG
J3 = E_remaining_total -(sum(N_candidate) * P_charger * dt);

%% J4 — TRANSFORMER OVERLOAD PENALTY (THERMAL STABILITY)
% Quadratic penalty above the 10 MVA thermal limit.
Trans_load = abs(S_bus(1)) / 1000;   % kVA → MVA
J4 = max(Trans_load - Trans_limit, 0)^2;

%% ---------------- TOTAL COST ----------------

J = w1*J1 + w2*J2 + w3*J3 + w4*J4;

end