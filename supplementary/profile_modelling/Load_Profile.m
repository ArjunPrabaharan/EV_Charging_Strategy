% Time vector (5-minute resolution)
t = 0:5:1440;     
h = t/60;         

% Base load components
base = 0.6;

morning = 0.20*exp(-((h-7)/2).^2);
midday  = 0.35*exp(-((h-13)/3).^2);
evening = 0.65*exp(-((h-19)/3).^2);

% Main load curve
load_profile = base + morning + midday + evening;

% ---- Small fluctuations ----
noise = 0.01*randn(size(h));      % very small random variations
noise = smoothdata(noise,'movmean',5); % smooth noise to avoid spikes

load_profile = load_profile + noise;

% Convert to per-unit
load_pu = load_profile / max(load_profile);

% Plot
figure
plot(h,load_pu,'LineWidth',2)
grid on
xlabel('Time (hours)')
ylabel('Load (p.u.)')
title('Domestic Load Profile')
xlim([0 24])
xticks(0:1:24)   % tick mark every hour
ylim([0 1.1])