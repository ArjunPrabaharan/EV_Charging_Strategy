function N_opt = run_PSO(N_avail_vec, E_remaining_total, num_stations, h, p_pv, V_prev1, V_prev2, V_prev3, t, dt, P_charger)

% ---------------- PROBLEM DEFINITION ----------------

CostFunction = @(x) evaluate_cost(x, h, p_pv, V_prev1, E_remaining_total, V_prev2, V_prev3, t, dt, P_charger);

nVar = num_stations;
VarSize = [1 nVar];

VarMin = zeros(1, nVar);
VarMax = N_avail_vec;

% ---------------- PSO PARAMETERS ----------------

MaxIt = 40;
nPop  = 20;

w     = 1;
wdamp = 0.95;
c1    = 1.5;
c2    = 2.0;

VelMax = 0.2*(VarMax - VarMin);
VelMin = -VelMax;

% ---------------- INITIALIZATION ----------------

empty_particle.Position = [];
empty_particle.Cost     = [];
empty_particle.Velocity = [];
empty_particle.Best.Position = [];
empty_particle.Best.Cost     = [];

particle = repmat(empty_particle, nPop, 1);

GlobalBest.Cost = inf;

for i = 1:nPop
    particle(i).Position = VarMin + rand(VarSize).*(VarMax - VarMin);
    particle(i).Velocity = zeros(VarSize);
    particle(i).Cost     = CostFunction(round(particle(i).Position));

    particle(i).Best.Position = particle(i).Position;
    particle(i).Best.Cost     = particle(i).Cost;

    if particle(i).Best.Cost < GlobalBest.Cost
        GlobalBest = particle(i).Best;
    end
end

% ---------------- PSO MAIN LOOP ----------------

for it = 1:MaxIt
    for i = 1:nPop

        particle(i).Velocity = w*particle(i).Velocity ...
            + c1*rand(VarSize).*(particle(i).Best.Position - particle(i).Position) ...
            + c2*rand(VarSize).*(GlobalBest.Position - particle(i).Position);

        particle(i).Velocity = max(particle(i).Velocity, VelMin);
        particle(i).Velocity = min(particle(i).Velocity, VelMax);

        particle(i).Position = particle(i).Position + particle(i).Velocity;

        IsOutside = (particle(i).Position < VarMin | particle(i).Position > VarMax);
        particle(i).Velocity(IsOutside) = -particle(i).Velocity(IsOutside);

        particle(i).Position = max(particle(i).Position, VarMin);
        particle(i).Position = min(particle(i).Position, VarMax);

        particle(i).Cost = CostFunction(round(particle(i).Position));

        if particle(i).Cost < particle(i).Best.Cost
            particle(i).Best.Position = particle(i).Position;
            particle(i).Best.Cost     = particle(i).Cost;

            if particle(i).Best.Cost < GlobalBest.Cost
                GlobalBest = particle(i).Best;
            end
        end
    end

    w = w * wdamp;
end

% ---------------- OUTPUT ----------------

N_opt = round(GlobalBest.Position);
N_opt = max(N_opt, VarMin);
N_opt = min(N_opt, VarMax);

end
