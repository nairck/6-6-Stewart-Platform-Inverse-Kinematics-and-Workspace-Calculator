function [roll, pitch, yaw] = rpy_from_rotation(R, axes)
%RPY_FROM_ROTATION  Roll / pitch / yaw [deg] from a rotation matrix (inverse
%   of rotation_rpy.m).  For the default 'XYZ' assignment R = Rx(roll) *
%   Ry(pitch) * Rz(yaw); for another assignment R = P R0 P' is first brought
%   back to R0 = P' R P.
%
%   From the matrix layout: R(1,3) = sin(pitch), R(2,3) = -sin(roll)cos(pitch),
%   R(3,3) = cos(roll)cos(pitch), R(1,2) = -cos(pitch)sin(yaw),
%   R(1,1) = cos(pitch)cos(yaw).  At |pitch| = 90 deg (never reached by this
%   tool's few-degree poses) roll and yaw are not separable: roll is set to 0
%   and the remaining rotation is assigned to yaw.
if nargin < 2 || isempty(axes), axes = 'XYZ'; end
if ~strcmpi(axes, 'XYZ')
    P = rpy_perm(axes);
    R = P' * R * P;
end
sp = max(-1, min(1, R(1,3)));
pitch = asin(sp);
if abs(sp) < 1 - 1e-12
    roll = atan2(-R(2,3), R(3,3));
    yaw  = atan2(-R(1,2), R(1,1));
else
    roll = 0;
    yaw  = atan2(R(2,1), R(2,2));
end
roll  = roll  * 180/pi;
pitch = pitch * 180/pi;
yaw   = yaw   * 180/pi;
end
