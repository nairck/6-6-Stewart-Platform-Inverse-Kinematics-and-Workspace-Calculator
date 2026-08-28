function inverse_solution = solve_inverse()
%SOLVE_INVERSE Read GUI inputs, compute inverse kinematics, update GUI, draw/animate platform
% Always displays values with three decimal places.

% Retrieve handles and helper
pi = get(gcf,'UserData');
getVal = @(f) str2double(get(pi.(f),'String'));
fmt = '%.3f';

% Base & platform XY coordinates
xsi = cellfun(getVal, arrayfun(@(i) sprintf('base%dx', i), 1:6, 'UniformOutput', false));
ysi = cellfun(getVal, arrayfun(@(i) sprintf('base%dy', i), 1:6, 'UniformOutput', false));
zsi = cellfun(getVal, arrayfun(@(i) sprintf('base%dz', i), 1:6, 'UniformOutput', false));
xmi = cellfun(getVal, arrayfun(@(i) sprintf('plat%dx', i), 1:6, 'UniformOutput', false));
ymi = cellfun(getVal, arrayfun(@(i) sprintf('plat%dy', i), 1:6, 'UniformOutput', false));
zmi = cellfun(getVal, arrayfun(@(i) sprintf('plat%dz', i), 1:6, 'UniformOutput', false));

% New posture = old + delta
roll  = getVal('roll_old')   + getVal('rolldelta');
pitch = getVal('pitch_old')  + getVal('pitchdelta');
yaw   = getVal('yaw_old')    + getVal('yawdelta');
px    = getVal('Pxval_old')  + getVal('Pxvaldelta');
py    = getVal('Pyval_old')  + getVal('Pyvaldelta');
pz    = getVal('Pzval_old')  + getVal('Pzvaldelta');

% Compute inverse kinematics (every joint has its own X, Y, Z)
inverse_solution = stew_inverse( ...
    xsi, ysi, zsi, xmi, ymi, zmi, ...
    roll, pitch, yaw, ...
    px, py, pz, rpy_axes_of(pi));

% Update leg lengths (1–6)
legs_new = inverse_solution(1:6);
for k = 1:6
    set(pi.(sprintf('leg%d',k)), 'String', sprintf(fmt, legs_new(k)));
end

% Compute deltas
% ——— Read & round old lengths ———
legs_old = round( ...
    arrayfun(@(i) getVal(sprintf('leg%d_old',i)), 1:6), 3 );
% ——— Read new lengths ———
legs_new = arrayfun(@(i) getVal(sprintf('leg%d',i)), 1:6);
% ——— Compute & round linear deltas ———
legs_delta    = round( legs_new - legs_old,           3 );
legs_absdelta = round( legs_new - getVal('zpdLegLength'), 3 );
% ——— Compute & round angular delta ———
legs_angdelta = round((legs_new - legs_old) * 360 / getVal('actuatorLead'), 1 );
% ——— split into revolutions + remainder (with proper sign & rounding) ———
leg_rev = fix( legs_angdelta / 360 );           % integer revolutions toward zero
leg_rem = legs_angdelta - leg_rev * 360;        % signed remainder in (–360, +360)
leg_rem = round( leg_rem, 1 );                  % nearest 0.1°
% if rounding gave exactly ±360°, roll it into the revs
idx360 = abs(leg_rem) == 360;
leg_rev(idx360) = leg_rev(idx360) + sign(legs_angdelta(idx360));
leg_rem(idx360) = 0;


% Update deltas in GUI
for k = 1:6
    set(pi.(sprintf('leg%ddelta',      k)), 'String', sprintf(fmt, legs_delta(k)));
    set(pi.(sprintf('leg%dabsdelta',   k)), 'String', sprintf(fmt, legs_absdelta(k)));
    set(pi.(sprintf('leg%dangledelta', k)), 'String', sprintf('%.1f', legs_angdelta(k)));
    set(pi.(sprintf('leg%drevrem',     k)), 'String', sprintf('(%d rev and %.1f°)', leg_rev(k), leg_rem(k)) );
end

% Update input-focus posture fields
set(pi.roll,   'String', sprintf(fmt, roll));
set(pi.pitch,  'String', sprintf(fmt, pitch));
set(pi.yaw,    'String', sprintf(fmt, yaw));
set(pi.Pxval,  'String', sprintf(fmt, px));
set(pi.Pyval,  'String', sprintf(fmt, py));
set(pi.Pzval,  'String', sprintf(fmt, pz));

% Draw or animate platform
plat_coords = inverse_solution(25:42);
if ~isfield(pi, 'animate') || pi.animate
    anim_plat(plat_coords);
else
    draw_plat(plat_coords);
end
end
