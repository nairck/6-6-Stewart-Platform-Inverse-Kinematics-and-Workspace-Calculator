function export_sketch_axes(ax, basePts, platPts, D)
%EXPORT_SKETCH_AXES  The main window's sketch drawn into ax for the exports:
%   joints (3 x 6 each) in the display frame D (default: the standard frame
%   of the given joints turned 180 deg like the window; previews of other
%   origins pass the primary origin's frame times R_o so all share one
%   orientation), default view, fitted; base / platform edges at half width
%   and 30 % opacity, legs as in the window, triad with arrowheads and letters.
if nargin < 4 || isempty(D)
    D = diag([-1 -1 1]) * standard_display_frame(basePts, platPts);
end
b = D * basePts;  p = D * platPts;
cla(ax); hold(ax, 'on'); set(ax, 'Clipping', 'off');
lw = 2;  edgeLw = 1;
legColors = {'#0072BD', '#D95319', '#EDB120', '#7E2F8E', '#77AC30', '#4DBEEE'};
baseCol = [0 0 0.545 0.3];  platCol = [0.635 0.078 0.184 0.3];    % RGBA, 30 % opacity
for e = [2 3; 4 5; 6 1]'
    plot3(ax, b(1, e), b(2, e), b(3, e), '-', 'LineWidth', edgeLw, 'Color', baseCol, 'Clipping', 'off');
end
for e = [1 2; 2 3; 3 4; 4 5; 5 6; 6 1]'
    plot3(ax, p(1, e), p(2, e), p(3, e), '-', 'LineWidth', edgeLw, 'Color', platCol, 'Clipping', 'off');
end
for i = 1:6
    if i == 1, style = '-.'; else, style = '-'; end
    plot3(ax, [b(1,i) p(1,i)], [b(2,i) p(2,i)], [b(3,i) p(3,i)], style, 'Marker', 'o', 'MarkerSize', 3, ...
        'LineWidth', lw, 'Color', legColors{i}, 'Clipping', 'off');
end
arrowLen = 150;
letters = {'X', 'Y', 'Z'};
for j = 1:3
    tip = arrowLen * D(:, j);
    plot3(ax, [0 tip(1)], [0 tip(2)], [0 tip(3)], '-k', 'LineWidth', 1, 'Clipping', 'off');
    arrow_head(ax, tip, D(:, j), arrowLen, 'k');
    lp = tip * 1.28;
    text(ax, lp(1), lp(2), lp(3), letters{j}, 'FontSize', 8, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'Clipping', 'off');
end
axis(ax, 'equal', 'off');
view(ax, [-30, 20]);
set(ax, 'CameraViewAngleMode', 'auto');
camva(ax, camva(ax) * 1.04);          % tighter fit than the window
end
