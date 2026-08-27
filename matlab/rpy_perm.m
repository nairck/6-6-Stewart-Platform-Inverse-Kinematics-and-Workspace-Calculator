function P = rpy_perm(axes)
%RPY_PERM  Permutation matrix of a roll/pitch/yaw axes assignment.
%   axes is 'XYZ' (default: roll about X, pitch about Y, yaw about Z), 'YZX'
%   or 'ZXY'; only these cyclic assignments are allowed so the three rotation
%   axes, in the order roll, pitch, yaw, always form a right-handed triad.
%   Column i of P is the unit vector of the axis that angle i rotates about.
axes = upper(char(axes));
if ~any(strcmp(axes, {'XYZ', 'YZX', 'ZXY'}))
    error('rpy_perm:badAxes', 'rpy axes must be XYZ, YZX or ZXY, got ''%s''', axes);
end
P = zeros(3);
for i = 1:3
    P(find('XYZ' == axes(i), 1), i) = 1;
end
end
