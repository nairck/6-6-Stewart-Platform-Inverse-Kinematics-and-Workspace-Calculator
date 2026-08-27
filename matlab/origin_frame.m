function [R, d] = origin_frame(origin, axes)
%ORIGIN_FRAME  Rotation R and offset d of an origin / point of interest,
%   both relative to Origin 1.  A point with Origin-1 coordinates p has
%   coordinates R' * (p - d) in this frame.  Origins without orientation
%   fields (older data) are treated as unrotated.
if nargin < 2 || isempty(axes), axes = 'XYZ'; end
f = @(name) origin_field(origin, name);
R = rotation_rpy(f('roll'), f('pitch'), f('yaw'), axes);
d = [f('dx'); f('dy'); f('dz')];
end

function v = origin_field(o, name)
if isfield(o, name) && ~isempty(o.(name))
    v = o.(name);
else
    v = 0;
end
end
