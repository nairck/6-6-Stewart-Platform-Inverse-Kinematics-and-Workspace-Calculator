function [roll2, pitch2, yaw2, px2, py2, pz2] = change_frame(M, e, roll, pitch, yaw, px, py, pz, axes)
%CHANGE_FRAME  Re-express a platform pose under the frame change q' = M q + e
%   applied to every joint coordinate, so that every leg vector is the same
%   physical vector (rotated by M) and every leg length is unchanged:
%
%       a' - (R' b' + t') = M [a - (R b + t)]     with a' = M a + e, b' = M b + e
%       =>  R' = M R M',   t' = M t + e - R' e
%
%   (For M = I this is shift_frame: t' = t + e - R e.)  The angles are
%   extracted for the roll/pitch/yaw axes assignment `axes`.
if nargin < 9 || isempty(axes), axes = 'XYZ'; end
e = e(:);
R2 = M * rotation_rpy(roll, pitch, yaw, axes) * M';
t2 = M * [px; py; pz] + e - R2 * e;
[roll2, pitch2, yaw2] = rpy_from_rotation(R2, axes);
px2 = t2(1);  py2 = t2(2);  pz2 = t2(3);
end
