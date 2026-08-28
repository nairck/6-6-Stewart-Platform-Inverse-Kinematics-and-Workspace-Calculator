function fit_sketch_view(ax, pts, marginFrac)
%FIT_SKETCH_VIEW  Centre the sketch in the axes and fill them with it.
%
%   The drawing is centred by putting the axes' data cube on the centre of the
%   points, and sized by measuring what MATLAB's automatic camera actually
%   framed and correcting the cube until the drawing fills the axes with
%   marginFrac left free on the limiting side.  Measuring instead of assuming
%   is what makes the result independent of how MATLAB derives its automatic
%   view angle (it frames the data box, not the drawing, so a fixed factor is
%   always wrong by some amount).  This mirrors the Python version's fit.
%
%   The camera itself is left on automatic, so rotating with the mouse and the
%   right-click view planes keep working and keep this scale.
%
%   ax   : axes holding the sketch
%   pts  : 3 x N points to frame (joints, the origin and the triad tips), in
%          the display frame, i.e. exactly what was drawn
%   marginFrac : free space kept on the limiting side (0.32 = 32 percent,
%                which matches the Python window)

if nargin < 3 || isempty(marginFrac), marginFrac = 0.32; end
pts = double(pts);
pts = pts(:, all(isfinite(pts), 1));
if isempty(pts), return; end

lo = min(pts, [], 2);  hi = max(pts, [], 2);
c = 0.5 * (lo + hi);                          % centre of what was drawn

% What the drawing measures on screen for this view (orthographic projection,
% so a projected coordinate is just a dot product).
[az, el] = view(ax);
w = [sind(az) * cosd(el); -cosd(az) * cosd(el); sind(el)];
u = cross([0; 0; 1], w);
if norm(u) < 1e-9, u = [1; 0; 0]; end         % looking straight down
u = u / norm(u);
v = cross(w, u);
x = u' * pts;  y = v' * pts;
rx = max(x) - min(x);  ry = max(y) - min(y);

old = get(ax, 'Units');
set(ax, 'Units', 'pixels');
pos = get(ax, 'Position');
set(ax, 'Units', old);
W = max(pos(3), 1);  H = max(pos(4), 1);

% Half-height the axes must show for the drawing to fit with its margin.
need = max([ry / 2, (rx / 2) * H / W, eps]) * (1 + marginFrac);

set(ax, 'DataAspectRatio', [1 1 1], ...
        'CameraPositionMode', 'auto', 'CameraTargetMode', 'auto', ...
        'CameraUpVectorMode', 'auto', 'CameraViewAngleMode', 'auto');

% First guess from how MATLAB frames a cube (it fits the enclosing sphere, so
% a cube of half-size need/sqrt(3) shows about `need`), then one or two
% measured corrections.  Starting close keeps the redraw from visibly settling.
r = max(need / sqrt(3), eps);
for k = 1:3
    set(ax, 'XLim', c(1) + [-r r], 'YLim', c(2) + [-r r], 'ZLim', c(3) + [-r r]);
    drawnow limitrate;                        % let the automatic camera settle
    cam = get(ax, 'CameraPosition');  tgt = get(ax, 'CameraTarget');
    dist = norm(cam - tgt);
    shown = dist * tand(get(ax, 'CameraViewAngle') / 2);   % half-height on screen
    if ~isfinite(shown) || shown <= 0, break; end
    ratio = need / shown;                     % > 1: too tight, < 1: too loose
    if abs(ratio - 1) < 0.02, break; end
    r = r * ratio;
end
end
