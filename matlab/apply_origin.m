function apply_origin(mainFig, newOrigins, newActive)
%APPLY_ORIGIN  Adopt a new origin list / selection and re-express everything.
%
%   An origin is a frame relative to Origin 1: offset d and orientation R
%   (roll, pitch, yaw about the roll/pitch/yaw axes).  With A the frame the
%   displayed values are currently in and B the newly selected origin, every
%   joint coordinate becomes q' = M q + e with M = R_B' R_A and
%   e = R_B' (d_A - d_B) (frame_transition.m); the old and new poses follow
%   change_frame.m (R' = M R M', t' = M t + e - R' e) so the platform does
%   not move physically and every leg length is unchanged.  The pose deltas
%   become new - old in the new frame, the sketch keeps the joints where they
%   are on screen (its display frame absorbs M) and the Edit-ZPD lock is
%   updated.  Search limits are left as entered: they are bounds in the active
%   frame's axes.  This is the ONLY place the active frame changes, so every
%   later solve, +/- adjust, save and workspace analysis automatically uses
%   the new origin.
%
%   newOrigins : struct array with fields name, dx, dy, dz, roll, pitch, yaw
%                (row 1 = Origin 1)
%   newActive  : 1-based index of the origin to use

pinfo  = get(mainFig, 'UserData');
getVal = @(f) str2double(get(pinfo.(f), 'String'));
setVal = @(f, v) set(pinfo.(f), 'String', sprintf('%.3f', v));
axes   = rpy_axes_of(pinfo);

oldO = pinfo.origins(pinfo.origin_active);
newO = newOrigins(newActive);
[M, e] = frame_transition(oldO, newO, axes);
changed = any(abs(e) > 0) || any(any(abs(M - eye(3)) > 1e-12));

set(0, 'CurrentFigure', mainFig);
if isfield(pinfo, 'animate'), animState = pinfo.animate; else, animState = true; end
pinfo.animate = false;                    % a frame change is redrawn, not animated
set(mainFig, 'UserData', pinfo);

if changed
    % Apply any pending (typed but unsolved) delta in the frame it was entered
    % in, so nothing the user typed is silently discarded.
    solve_inverse();

    % joints: q' = M q + e  (the point of interest becomes the origin and its
    % axes become the coordinate axes)
    for i = 1:6
        for grp = {'base', 'plat'}
            names = {sprintf('%s%dx', grp{1}, i), sprintf('%s%dy', grp{1}, i), sprintf('%s%dz', grp{1}, i)};
            q = M * [getVal(names{1}); getVal(names{2}); getVal(names{3})] + e;
            for k = 1:3
                setVal(names{k}, q(k));
            end
        end
    end

    % poses (old and new): R' = M R M', t' = M t + e - R' e
    for sfx = {'_old', ''}
        s = sfx{1};
        [r2, p2, y2, px, py, pz] = change_frame(M, e, ...
            getVal(['roll'  s]), getVal(['pitch' s]), getVal(['yaw'   s]), ...
            getVal(['Pxval' s]), getVal(['Pyval' s]), getVal(['Pzval' s]), axes);
        setVal(['roll'  s], r2);  setVal(['pitch' s], p2);  setVal(['yaw'   s], y2);
        setVal(['Pxval' s], px);  setVal(['Pyval' s], py);  setVal(['Pzval' s], pz);
    end
    % deltas = new - old, read back from the displayed 3-decimal values so that
    % old + delta reproduces the displayed new pose exactly
    for t = {'roll', 'pitch', 'yaw', 'Pxval', 'Pyval', 'Pzval'}
        setVal([t{1} 'delta'], getVal(t{1}) - getVal([t{1} '_old']));
    end
    % The sketch's display frame is left exactly as it is, so the triad keeps
    % pointing the same way on screen and the user's view angle is kept; the
    % coordinates have moved, so draw_plat's fit simply re-centres the drawing
    % in the axes.  (Deriving the frame again here would re-orient the sketch,
    % because the standard frame depends on where the origin sits.)
    if ~isfield(pinfo, 'sketch_disp') || isempty(pinfo.sketch_disp)
        pinfo.sketch_disp = eye(3);
    end
    pinfo.sketch_auto = false;
end

% the Incremental Adj. Table set-up follows each origin by name (a renamed or
% new origin starts with nothing ticked)
oldCfg = adj_config_normalise(pinfo.adj_config, numel(pinfo.origins));
newCfg = adj_config_default(numel(newOrigins));
newCfg.decimals = oldCfg.decimals;
for i = 1:numel(newOrigins)
    j = find(strcmp({pinfo.origins.name}, newOrigins(i).name), 1);
    if ~isempty(j)
        newCfg.masks(i, :) = oldCfg.masks(j, :);
        newCfg.turns(i, :) = oldCfg.turns(j, :);
        newCfg.labels(i, :) = oldCfg.labels(j, :);
    end
end
pinfo.adj_config    = newCfg;
pinfo.origins       = newOrigins;
pinfo.origin_active = newActive;
set(mainFig, 'UserData', pinfo);
refresh_origin_ui(mainFig);                % button label + Edit-ZPD lock state

desc = sprintf('X %.3f, Y %.3f, Z %.3f mm', newO.dx, newO.dy, newO.dz);
if any(abs([newO.roll, newO.pitch, newO.yaw]) > 0)
    desc = sprintf('%s, roll %.3f, pitch %.3f, yaw %.3f deg', desc, newO.roll, newO.pitch, newO.yaw);
end
if changed
    solve_inverse();                       % legs unchanged; redraw about the new origin
    color_input_box();
    fprintf('origin changed to ''%s'' (%s from Origin 1). Joints, poses, illustration and workspaces are now referenced to this frame.\n', ...
        newO.name, desc);
else
    fprintf('origins updated; current origin: ''%s'' (%s from Origin 1).\n', newO.name, desc);
end
pinfo = get(mainFig, 'UserData');         % it has been rewritten meanwhile
pinfo.animate = animState;
set(mainFig, 'UserData', pinfo);
end
