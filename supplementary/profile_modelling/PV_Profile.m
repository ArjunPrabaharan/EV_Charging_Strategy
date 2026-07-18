clc; clear; close all;

% PV Profile Generation using random noise

% Time vector (24 hours with 1-min resolution)
t = linspace(0,24,1440);   % hours

% Ideal solar irradiance curve (bell shaped)
sunrise = 6;
sunset  = 18;

irradiance = zeros(size(t));

for i = 1:length(t)
    if t(i) >= sunrise && t(i) <= sunset
        irradiance(i) = sin(pi*(t(i)-sunrise)/(sunset-sunrise));
    end
end

irradiance = irradiance / max(irradiance);   % per unit normalization

% Cloud intermittency model (loss factor between 0 and 1)
rng('shuffle')

noise = randn(size(t));           % random signal
smooth_noise = movmean(noise,50); % create cloud clusters

% Convert to attenuation factor (0 to 1)
cloud_factor1 = 1 - 0.1*abs(smooth_noise)/max(abs(smooth_noise));
cloud_factor2 = 1 - 1*abs(smooth_noise)/max(abs(smooth_noise));

% PV output
pv_output1 = irradiance .* cloud_factor1;
pv_output2 = irradiance .* cloud_factor2;

pv_output_5min = pv_output2(1:5:end);
pv_output_15min = pv_output2(1:15:end);

% Plot
figure;
% plot(t, irradiance,'LineWidth',2);
hold on;
% plot(t, pv_output1,'b','LineWidth',1.5);
% plot(t(1:15:end), pv_output_15min,'r','LineWidth',1.5);
plot(t(1:15:end), pv_output_15min,'LineWidth',1.5);

xlabel('Time (hours)');
ylabel('PV Output (per unit)');
title('Daily PV Generation Profile with Cloud Intermittency');
% legend('Expected Profile','PV with Cloud Intermitency');
grid on;
xlim([0 24]);











