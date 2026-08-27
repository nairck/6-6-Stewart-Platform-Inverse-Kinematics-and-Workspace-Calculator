% =========================================================================
% Filename:        RUN_HEXAPOD_CALCULATOR.m
%
% Author:          Joe Brown (CSU Sacramento) – August 4, 2006  
% Version:         see hexapod_version.m (matches the Python package version)
% Modified by:     Adam Johnson – August 2022 to April 2025
%
% Description:
% Launches the SPIDERS Hexapod Calculator GUI for configuring, solving, and
% analyzing the inverse kinematics of a hexapod (6-6 Gough-Stewart platform). The tool is 
% tailored for practical use with manually articulating turnbuckles and 
% allows for absolute and incremental posture calculations, workspace analysis, 
% and visualization.
%
% Key Features:
%   - Full GUI for configuring geometry, constraints, and posture deltas
%   - Inverse kinematics solver with absolute and realtive output of prismatic leg lengths
%   - Automatic handling of saved posture/configuration data via "formdata.txt"
%   - Recall and overwrite functionality for previous system posture/configuration
%   - Orientation and reachable workspace calculation with scalable resolution
%   - Automatic export of results to ".mat" files ("..._workspace_NEW.mat")
%   - Workspace plotting recall via "..._workspace_RECALL.mat" file variants
%   - 3D plot generation with closed surface mapping and axis overlays
%   - Optional PNG export of workspace plots at multiple view angles
%
% Usage:
%   - Run this script to launch the GUI.
%   - Input base/platform coordinates, ZPD height, and workspace constraints.
%   - Use a change in posture INPUT to compute new leg length adjustment 
%       via "Solve Inverse Kinematics".
%   - Update posture and save configurations using "Update Old Posture" and 
%       "Save Everything".
%   - Compute workspaces using "Draw Reachable Workspace" or 
%       "Draw Orientation Workspace", then export PNG images.
%   - Use "Export PNG" to select new or recall prior and export results.
%
% Requirements:
%   - MATLAB (R2020b or later recommended) with GUI support enabled
%   - Symbolic Math Toolbox (MathWorks, version 8.7 or later recommended)
%   - 64-bit Windows operating system (tested on Windows 11)
%   - Precompiled 64-bit MEX files (included)
%
% Notes:
%   - MEX files are OS- and architecture-dependent, but do not require 
%     MATLAB Coder on the user s machine unless recompiling codegen folder.
%   - Workspace image export supports rotation via number of output images.
%   - PNG outputs are organized into dedicated export folders.
% =========================================================================



% run main function to open GUI stew,name_string
MAIN_GUI('stew')





