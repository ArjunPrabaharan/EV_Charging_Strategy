function selected_idx = fuzzy_EV_priority(fis, available_idx, EV_energy_left_s, energy_req_s, departure_s, arrival_s, t, N_s)

%==========================================================================
%  Fuzzy Logic EV Charger Allocation (Lower Layer).
%
%  Assigns a Mamdani fuzzy priority score to each available EV and
%  returns the indices of the top N_s EVs selected for charging.
%
%  INPUTS:
%    fis              - Mamdani FIS object (built once before main loop)
%    available_idx    - column vector of EV indices that are present and
%                       still need energy at this station
%    EV_energy_left_s - remaining energy (kWh) for every EV at station s
%    energy_req_s     - original required energy (kWh) per EV at station s
%    departure_s      - departure interval per EV
%    arrival_s        - arrival interval per EV
%    t                - current simulation interval
%    N_s              - number of charger slots allocated to this station
%                       by PSO (upper layer output)
%
%  OUTPUT:
%    selected_idx - column vector of EV indices chosen to receive a charger
%==========================================================================

if isempty(available_idx) || N_s == 0
    selected_idx = [];
    return;
end

n = length(available_idx);

% If charger slots >= available EVs, all EVs get a charger
if N_s >= n
    selected_idx = available_idx;
    return;
end

% -------- BUILD FUZZY INPUT MATRIX (n x 3) --------

fuzz_in = zeros(n, 3);

for k = 1:n
    i = available_idx(k);

    % Input 1: Energy Demand  (0 = fully charged, 1 = not charged at all)
    ed = EV_energy_left_s(i) / max(energy_req_s(i), 1e-6);
    ed = min(max(ed, 0), 1);

    % Input 2: Remaining Time  (intervals until departure)
    rt = max(departure_s(i) - t, 0);

    % Input 3: Fairness Index  (intervals since arrival)
    fi = max(t - arrival_s(i), 0);

    fuzz_in(k, :) = [ed, rt, fi];
end

% -------- EVALUATE MAMDANI FIS --------

scores = evalfis(fis, fuzz_in);    % returns n x 1 priority scores
scores(isnan(scores)) = 0;         % guard against degenerate cases

% -------- SELECT TOP N_s EVs --------

[~, rank_order] = sort(scores, 'descend');
selected_local  = rank_order(1:N_s);
selected_idx    = available_idx(selected_local);

end
