function apply_axis_map(mainFig, M, mapping)
%APPLY_AXIS_MAP  Relabel the axes with the signed permutation M (new = M*current).
%
%   Applied to everything expressed in coordinates: every base and platform
%   joint (X, Y, Z), the old and new poses (translation p' = M p, rotation
%   R' = M R M' re-expressed as roll / pitch / yaw), the pose deltas (new - old),
%   the search limits (each axis interval follows its axis, mirrored on a sign
%   flip), the origin offsets (d' = M d) and the running +/- column totals.
%   Leg lengths are invariant.  The sketch keeps the joints where they are on
%   screen (see draw_plat.m) and only its coordinate triad changes.  The
%   field labels stay X, Y, Z.
%
%   mapping : cell array {mapX, mapY, mapZ} of the chosen labels (for the message)

if all(all(abs(M - eye(3)) < 1e-12))
    disp('coordinate mapping is the identity - nothing changed.');
    return;
end
pinfo  = get(mainFig, 'UserData');
getVal = @(f) str2double(get(pinfo.(f), 'String'));
setVal = @(f, v) set(pinfo.(f), 'String', sprintf('%.3f', v));
axes   = rpy_axes_of(pinfo);           % roll/pitch/yaw axes assignment (unchanged here)

set(0, 'CurrentFigure', mainFig);
animState = get(pinfo.animate_but, 'Value');
set(pinfo.animate_but, 'Value', 0);      % an axis change is redrawn, not animated

% apply any typed-but-unsolved delta in the axes it was entered in
solve_inverse();

% joints
for i = 1:6
    for grp = {'base', 'plat'}
        names = {sprintf('%s%dx', grp{1}, i), sprintf('%s%dy', grp{1}, i), sprintf('%s%dz', grp{1}, i)};
        v = M * [getVal(names{1}); getVal(names{2}); getVal(names{3})];
        for k = 1:3
            setVal(names{k}, v(k));
        end
    end
end

% poses (old and new): p' = M p ; R' = M R M'
for sfx = {'_old', ''}
    s = sfx{1};
    R = rotation_rpy(getVal(['roll' s]), getVal(['pitch' s]), getVal(['yaw' s]), axes);
    [r2, p2, y2] = rpy_from_rotation(M * R * M', axes);
    t2 = M * [getVal(['Pxval' s]); getVal(['Pyval' s]); getVal(['Pzval' s])];
    setVal(['roll' s], r2);  setVal(['pitch' s], p2);  setVal(['yaw' s], y2);
    setVal(['Pxval' s], t2(1));  setVal(['Pyval' s], t2(2));  setVal(['Pzval' s], t2(3));
end
for t = {'roll', 'pitch', 'yaw', 'Pxval', 'Pyval', 'Pzval'}
    setVal([t{1} 'delta'], getVal(t{1}) - getVal([t{1} '_old']));
end

% search limits: new axis j takes the interval of the current axis k it comes
% from (M(j,k) = s); a sign flip mirrors it: [min, max] -> [-max, -min].
% Each angle belongs to the coordinate axis it rotates about (the
% roll/pitch/yaw axes assignment), and its interval follows that axis.
angleOfAxis = containers.Map({'X','Y','Z'}, {'', '', ''});
angleNames = {'roll', 'pitch', 'yaw'};
for i = 1:3
    angleOfAxis(axes(i)) = angleNames{i};
end
axisAngles = {angleOfAxis('X'), angleOfAxis('Y'), angleOfAxis('Z')};
for keys = {{'px', 'py', 'pz'}, axisAngles}
    kk = keys{1};
    mins = [getVal([kk{1} 'min']), getVal([kk{2} 'min']), getVal([kk{3} 'min'])];
    maxs = [getVal([kk{1} 'max']), getVal([kk{2} 'max']), getVal([kk{3} 'max'])];
    for j = 1:3
        [~, k] = max(abs(M(j,:)));
        if M(j,k) > 0
            newMin = mins(k);  newMax = maxs(k);
        else
            newMin = -maxs(k); newMax = -mins(k);
        end
        setVal([kk{j} 'min'], newMin);
        setVal([kk{j} 'max'], newMax);
    end
end

% origins: offsets d' = M d, orientations R' = M R M'
for i = 1:numel(pinfo.origins)
    d = M * [pinfo.origins(i).dx; pinfo.origins(i).dy; pinfo.origins(i).dz];
    pinfo.origins(i).dx = round(d(1), 3);
    pinfo.origins(i).dy = round(d(2), 3);
    pinfo.origins(i).dz = round(d(3), 3);
    [Ro, ~] = origin_frame(pinfo.origins(i), axes);
    [r2, p2, y2] = rpy_from_rotation(M * Ro * M', axes);
    pinfo.origins(i).roll  = round(r2, 3);
    pinfo.origins(i).pitch = round(p2, 3);
    pinfo.origins(i).yaw   = round(y2, 3);
end
% the sketch keeps the joints exactly where they are on screen; only its
% coordinate triad changes:  display = D_old * current = D_old * M' * new
if ~isfield(pinfo, 'sketch_disp'), pinfo.sketch_disp = eye(3); end
pinfo.sketch_disp = pinfo.sketch_disp * M';
pinfo.sketch_auto = false;
set(mainFig, 'UserData', pinfo);

% running +/- column totals follow their axis (with sign)
for grp = {'si', 'mi'}
    old = zeros(3,1);
    axes_ = 'xyz';
    for k = 1:3
        val = getappdata(mainFig, [axes_(k) grp{1} '_totalOffset']);
        if ~isempty(val), old(k) = val; end
    end
    newT = M * old;
    for k = 1:3
        setappdata(mainFig, [axes_(k) grp{1} '_totalOffset'], newT(k));
    end
end

refresh_origin_ui(mainFig);
solve_inverse();                         % legs unchanged; redraw in the new axes
color_input_box();
fprintf('coordinate axes relabelled: current X -> %s, Y -> %s, Z -> %s. Joints, poses, limits and origins are now expressed in the new axes; the sketch keeps its view and its triad shows the new axes.\n', ...
    mapping{1}, mapping{2}, mapping{3});
set(pinfo.animate_but, 'Value', animState);
end

