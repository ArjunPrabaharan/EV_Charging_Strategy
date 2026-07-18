% STARTUP  -->  Add the project folders to the MATLAB path.
%
% Run it once before running any simulation:
%
%   >> startup
%   >> Uncoordinated_24Hrs      % must be run FIRST (creates the baseline)
%   >> Coordinated_24Hrs        % uses the baseline for comparison plots
%
% The simulation scripts read their inputs by bare filename
% (e.g. readtable('EV_Data_1.xlsx'), load('linedata33bus.m')), so both
% src/ and data/ must be on the MATLAB path.

% Folder containing this file (src/), and the repository root one level up.
srcDir  = fileparts(mfilename('fullpath'));
rootDir = fileparts(srcDir);

addpath(srcDir);
addpath(fullfile(rootDir, 'data'));

fprintf('Project paths added:\n  %s\n  %s\n', srcDir, fullfile(rootDir, 'data'));
fprintf('Run Uncoordinated_24Hrs first, then Coordinated_24Hrs.\n');
