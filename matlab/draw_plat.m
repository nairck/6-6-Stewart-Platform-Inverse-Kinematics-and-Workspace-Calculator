function draw_plat(plat_coords)
% DRAW_PLAT   Draw hexapod base, platform, and legs in 3D
%
%   draw_plat(plat_coords) reads the base coordinates from the GUI,
%   uses plat_coords (1×18) for the platform, and redraws
%   the entire mechanism cleanly and efficiently.

% clear and prepare axes
cla; hold on;
axis vis3d equal off
rotate3d on
% A double-click inside the sketch resets the view.  MATLAB's own double-click
% reset restores the camera it saved when rotation was switched on, which is
% not the standard view; running our reset afterwards makes the double-click do
% exactly what the Reset View button does.
set(rotate3d(gcf), 'ActionPostCallback', @(f, ~) sketch_click_done(f));
plotinfo = get(gcf,'UserData');
% Lines are clipped to the axes' data box by default while text is not; the
% axes rectangle itself is the only boundary the sketch should have, so every
% object drawn below has 'Clipping' off (anim_plat.m reuses these handles).
set(gca, 'Clipping', 'off');

% Sketch display frame: after a "Change Coords." relabelling the numbers are
% in the new axes but the drawing must not move, so every point is plotted as
% D*p (D = original sketch axes) and the triad shows where the new X, Y, Z
% axes now point (the columns of D).  Identity until the axes are relabelled.
if ~isfield(plotinfo, 'sketch_disp') || isempty(plotinfo.sketch_disp), plotinfo.sketch_disp = eye(3); end
if ~isfield(plotinfo, 'sketch_auto'), plotinfo.sketch_auto = true; end

%── Read base points from GUI ───────────────────────────────────────────
base_x = arrayfun(@(i) ...
    str2double(get(plotinfo.(sprintf('base%dx',i)),'String')), 1:6);
base_y = arrayfun(@(i) ...
    str2double(get(plotinfo.(sprintf('base%dy',i)),'String')), 1:6);
base_z = arrayfun(@(i) ...
    str2double(get(plotinfo.(sprintf('base%dz',i)),'String')), 1:6);
rawBase = [ base_x; base_y; base_z ];        % 3×6 (each base joint has its own Z)
rawPlat = reshape(plat_coords, 3, 6);        % plat_coords = [x1 y1 z1, x2 y2 z2, ..., x6 y6 z6]
if plotinfo.sketch_auto
    % standard view chosen from the geometry (start-up, origin change); a
    % Change Coords. relabelling keeps the frame instead (apply_axis_map.m)
    % turned 180 degrees about the vertical (the triad points the other way);
    % the workspace windows use the unturned frame (see the sweeps)
    plotinfo.sketch_disp = diag([-1 -1 1]) * standard_display_frame(rawBase, rawPlat);
    plotinfo.sketch_auto = false;
    set(gcf, 'UserData', plotinfo);
end
D = plotinfo.sketch_disp;
basePts = D * rawBase;                        % display frame
platPts = D * rawPlat;                        % display frame

line_size  = 2;
arrow_len  = 150;

%── Draw coordinate axes (the current X, Y, Z, wherever they now point) ───
letters = {'X','Y','Z'};
for j = 1:3
    tip = arrow_len * D(:,j);
    plot3([0 tip(1)],[0 tip(2)],[0 tip(3)], '-k', 'LineWidth',1, 'Clipping','off');
    arrow_head(gca, tip, D(:,j), arrow_len, 'k');
    lp = tip * 1.28;      % letter beyond the tip along the arrow, clear of the arrowhead
    text(lp(1),lp(2),lp(3), letters{j},'FontSize',8, 'HorizontalAlignment','center', 'VerticalAlignment','middle', 'Clipping','off');
end

%── Draw base triangular edges as persistent line handles ─────────
baseEdges = [2 3; 4 5; 6 1];
for e = 1:3
    i1 = baseEdges(e,1); i2 = baseEdges(e,2);
    % create the line once, store it in plotinfo.p13..p15
    plotinfo.(sprintf('p%d',12+e)) = plot3( ...
        basePts(1,[i1 i2]), ...
        basePts(2,[i1 i2]), ...
        basePts(3,[i1 i2]), ...
        '-b','LineWidth',line_size,'Color','#00008b','Clipping','off' ...
        );
end
set(gcf,'UserData',plotinfo);


%── Draw legs from base → platform ──────────────────────────────────────
legColors = {'#0072BD','#D95319','#EDB120','#7E2F8E','#77AC30','#4DBEEE'};
for i = 1:6
    style = '-.';  % leg 1 is dash-dot, the others solid
    if i > 1, style = '-'; end
    plotinfo.(sprintf('p%d',i)) = plot3( ...
        [basePts(1,i) platPts(1,i)], ...
        [basePts(2,i) platPts(2,i)], ...
        [basePts(3,i) platPts(3,i)], ...
        style, 'Marker','o', 'MarkerSize',3, ...
        'LineWidth',line_size, 'Color',legColors{i}, 'Clipping','off' ...
        );
end

%── Draw platform hexagon edges (1–2,2–3,…,6–1) ────────────────────────
platformEdges = [1 2; 2 3; 3 4; 4 5; 5 6; 6 1];
for e = 1:size(platformEdges,1)
    i1 = platformEdges(e,1); i2 = platformEdges(e,2);
    idx = e + 6;  % handles p7…p12
    plotinfo.(sprintf('p%d',idx)) = plot3( ...
        [platPts(1,i1) platPts(1,i2)], ...
        [platPts(2,i1) platPts(2,i2)], ...
        [platPts(3,i1) platPts(3,i2)], ...
        '-r', 'MarkerSize',3, 'LineWidth',line_size, 'Color','#A2142F', 'Clipping','off' ...
        );
end

%── Fit the drawing to the axes for the current view ──────────────────
% The drawing is centred in the axes and magnified until its projected
% bounding box fills them, with a small margin on the limiting side (see
% fit_sketch_view.m, which mirrors the Python version's fit), then frozen
% (vis3d) so mouse rotation does not rescale it.  Re-done on every full redraw
% (start-up, origin or axis change); anim_plat.m keeps it.
axis(gca, 'equal');
fitPts = [basePts, platPts, zeros(3,1), arrow_len * D];   % joints, origin, triad tips
fit_sketch_view(gca, fitPts);
axis(gca, 'vis3d');
plotinfo.fit_pts = fitPts;            % Reset View re-uses them
set(gcf, 'UserData', plotinfo);

%── Store updated handles and finish ────────────────────────────────────
set(gcf,'UserData',plotinfo);
end
