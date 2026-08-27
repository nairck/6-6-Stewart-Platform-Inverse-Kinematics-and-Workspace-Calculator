function [roll2, pitch2, yaw2] = convert_rpy_axes(roll, pitch, yaw, oldAxes, newAxes)
%CONVERT_RPY_AXES  The same physical rotation described with another
%   roll/pitch/yaw axes assignment (see rpy_perm.m).
[roll2, pitch2, yaw2] = rpy_from_rotation(rotation_rpy(roll, pitch, yaw, oldAxes), newAxes);
end
