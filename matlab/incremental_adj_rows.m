function rows = incremental_adj_rows(mainFig, selections, fromHome)
%INCREMENTAL_ADJ_ROWS  Rows of the incremental adjustment table (identical
%   maths to the Python adj_table.py).
%
%   For every ticked (origin, axis) pair: the ratio of actuator rotation each
%   leg needs for a small move of the platform in the + direction of that
%   axis of that origin's frame, normalized so the leg turning the most has
%   magnitude 1 (sign kept).  All in the frame the values are displayed in
%   (frame A): pose (R, t) from the displayed roll/pitch/yaw/X/Y/Z with the
%   rpy axes assignment; origin o has (R_o, d_o) relative to Origin 1, so in
%   frame A its point is c = R_A' (d_o - d_A) and its axis n = R_A' R_o e_a.
%   Translation: t' = t +/- delta n.  Rotation about the origin's point and
%   axis: Rot = Rodrigues(n, +/- delta), R' = Rot R, t' = Rot (t - c) + c.
%   dL = (L(+delta) - L(-delta)) / 2 (central difference), dtheta = dL*360/lead,
%   ratio = dtheta / max|dtheta|.
%
%   selections : logical numel(origins) x 6 (columns X, Y, Z, Roll, Pitch, Yaw)
%   rows       : struct array with fields origin (index), name, axis ('+X'...),
%                ratios (1x6), dtheta (1x6), ref, ones (legs with |ratio| = 1)
DELTA_MM = 0.1;  DELTA_DEG = 0.01;
AXES = {'X', 'Y', 'Z', 'Roll', 'Pitch', 'Yaw'};
pinfo  = get(mainFig, 'UserData');
getVal = @(f) str2double(get(pinfo.(f), 'String'));
axesRpy = rpy_axes_of(pinfo);
a = zeros(6,3);  b = zeros(6,3);
for i = 1:6
    a(i,:) = [getVal(sprintf('base%dx',i)), getVal(sprintf('base%dy',i)), getVal(sprintf('base%dz',i))];
    b(i,:) = [getVal(sprintf('plat%dx',i)), getVal(sprintf('plat%dy',i)), getVal(sprintf('plat%dz',i))];
end
% From Home: the zero-displacement configuration, which is the zero pose in
% every origin's frame.  From New: the pose now displayed in the main window.
if nargin < 3 || isempty(fromHome), fromHome = true; end
if fromHome
    R = eye(3);
    t = zeros(3, 1);
else
    R = rotation_rpy(getVal('roll'), getVal('pitch'), getVal('yaw'), axesRpy);
    t = [getVal('Pxval'); getVal('Pyval'); getVal('Pzval')];
end
lead = getVal('actuatorLead');  if isnan(lead) || lead == 0, lead = 1; end
[R_A, d_A] = origin_frame(pinfo.origins(pinfo.origin_active), axesRpy);
E = eye(3);
rows = struct('origin', {}, 'name', {}, 'axis', {}, 'ratios', {}, 'dtheta', {}, 'ref', {}, 'ones', {});
for oi = 1:numel(pinfo.origins)
    [R_o, d_o] = origin_frame(pinfo.origins(oi), axesRpy);
    c = R_A' * (d_o - d_A);
    for ai = 1:6
        if ~selections(oi, ai), continue; end
        if ai <= 3
            e = E(:, ai);
        else
            e = E(:, find('XYZ' == axesRpy(ai - 3), 1));
        end
        n = R_A' * R_o * e;
        if ai <= 3
            Lp = leg_lengths(a, b, R, t + DELTA_MM * n);
            Lm = leg_lengths(a, b, R, t - DELTA_MM * n);
        else
            Rp = rodrigues(n, DELTA_DEG);  Rm = rodrigues(n, -DELTA_DEG);
            Lp = leg_lengths(a, b, Rp * R, Rp * (t - c) + c);
            Lm = leg_lengths(a, b, Rm * R, Rm * (t - c) + c);
        end
        dL = 0.5 * (Lp - Lm);
        dtheta = dL * 360 / lead;
        [mx, ref] = max(abs(dtheta));
        if mx > 0
            ratios = dtheta / mx;
        else
            ratios = zeros(1, 6);
        end
        r.origin = oi;  r.name = pinfo.origins(oi).name;  r.axis = ['+' AXES{ai}];
        r.ratios = ratios;  r.dtheta = dtheta;  r.ref = ref;
        r.ones = find(abs(abs(ratios) - 1) < 1e-9);
        rows(end+1) = r; %#ok<AGROW>
    end
end
end


function L = leg_lengths(a, b, R, t)
p = (R * b')' + repmat(t(:)', 6, 1);
L = sqrt(sum((a - p).^2, 2))';
end


function Rm = rodrigues(n, angleDeg)
n = n(:) / max(norm(n), eps);
th = angleDeg * pi / 180;
Kx = [0 -n(3) n(2); n(3) 0 -n(1); -n(2) n(1) 0];
Rm = eye(3) + sin(th) * Kx + (1 - cos(th)) * (Kx * Kx);
end
