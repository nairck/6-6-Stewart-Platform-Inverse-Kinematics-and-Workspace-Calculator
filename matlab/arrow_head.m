function h = arrow_head(ax, tip, direction, len, color)
%ARROW_HEAD  Solid 3D cone arrowhead with its apex at tip, pointing along direction.
%   The cone's axis runs back from the tip along -direction, so the head
%   points in the arrow's own direction in every view (a flat marker would
%   not).  Cone height is 12 % and base radius 4 % of the arrow length len.
%   Used by draw_plat.m (sketch triad) and change_coords_dialog.m (dialog triads).
d = direction(:)' / max(norm(direction), eps);
tip = tip(:)';
hgt = 0.12 * len;
rad = 0.04 * len;
if abs(d(1)) < 0.9
    helper = [1 0 0];
else
    helper = [0 1 0];
end
u = cross(d, helper); u = u / norm(u);
v = cross(d, u);
n = 12;
ang = (0:n-1) * 2*pi / n;
centre = tip - hgt * d;
ring = centre + rad * (cos(ang)' * u + sin(ang)' * v);    % n x 3
V = [tip; ring];
F = [ones(n,1), (2:n+1)', [3:n+1, 2]'];                    % side faces
h = patch(ax, 'Faces', F, 'Vertices', V, 'FaceColor', color, 'EdgeColor', color, ...
          'LineWidth', 0.3, 'Clipping', 'off');
patch(ax, 'Faces', 2:n+1, 'Vertices', V, 'FaceColor', color, 'EdgeColor', 'none', ...
      'Clipping', 'off');                                  % closed base
end
