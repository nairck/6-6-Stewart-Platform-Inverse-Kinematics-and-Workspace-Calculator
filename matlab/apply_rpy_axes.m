function apply_rpy_axes(mainFig, newAxes)
%APPLY_RPY_AXES  Change which coordinate axis roll, pitch and yaw rotate about
%   (cyclic assignments only, see rpy_perm.m).
%
%   The physical rotations do not change: the old and new poses and every
%   origin's orientation are re-extracted for the new assignment
%   (convert_rpy_axes), the deltas become new - old, and each angle's search
%   limits follow the axis they belong to.  The constraint labels show the
%   new axes; the file records the assignment on its rpy_axes line.
pinfo  = get(mainFig, 'UserData');
getVal = @(f) str2double(get(pinfo.(f), 'String'));
setVal = @(f, v) set(pinfo.(f), 'String', sprintf('%.3f', v));
oldAxes = rpy_axes_of(pinfo);
newAxes = upper(char(newAxes));
if ~any(strcmp(newAxes, {'XYZ', 'YZX', 'ZXY'})) || strcmp(newAxes, oldAxes)
    return;
end
set(0, 'CurrentFigure', mainFig);
animState = get(pinfo.animate_but, 'Value');
set(pinfo.animate_but, 'Value', 0);
solve_inverse();                            % apply any pending delta first

for sfx = {'_old', ''}
    s = sfx{1};
    [r2, p2, y2] = convert_rpy_axes(getVal(['roll' s]), getVal(['pitch' s]), getVal(['yaw' s]), ...
                                    oldAxes, newAxes);
    setVal(['roll' s], r2);  setVal(['pitch' s], p2);  setVal(['yaw' s], y2);
end
for t = {'roll', 'pitch', 'yaw', 'Pxval', 'Pyval', 'Pzval'}
    setVal([t{1} 'delta'], getVal(t{1}) - getVal([t{1} '_old']));
end

% each angle's [min, max] follows the axis it rotates about
names = {'roll', 'pitch', 'yaw'};
mins = [getVal('rollmin'), getVal('pitchmin'), getVal('yawmin')];
maxs = [getVal('rollmax'), getVal('pitchmax'), getVal('yawmax')];
for j = 1:3
    i = find(oldAxes == newAxes(j), 1);
    setVal([names{j} 'min'], mins(i));
    setVal([names{j} 'max'], maxs(i));
end

for i = 2:numel(pinfo.origins)
    o = pinfo.origins(i);
    [r2, p2, y2] = convert_rpy_axes(o.roll, o.pitch, o.yaw, oldAxes, newAxes);
    pinfo.origins(i).roll  = round(r2, 3);
    pinfo.origins(i).pitch = round(p2, 3);
    pinfo.origins(i).yaw   = round(y2, 3);
end

pinfo.rpy_axes = newAxes;
set(mainFig, 'UserData', pinfo);
refresh_angle_labels(mainFig);
solve_inverse();
color_input_box();
fprintf('rotation angles reassigned: roll about %s, pitch about %s, yaw about %s (was %s, %s, %s). Poses, limits and origins re-expressed; nothing moved.\n', ...
    newAxes(1), newAxes(2), newAxes(3), oldAxes(1), oldAxes(2), oldAxes(3));
set(pinfo.animate_but, 'Value', animState);
end
