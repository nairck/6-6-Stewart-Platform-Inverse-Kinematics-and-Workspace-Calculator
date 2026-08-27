function R = rotation_rpy(roll, pitch, yaw, axes)
%ROTATION_RPY  Platform rotation matrix from roll, pitch, yaw [deg].
%   R = Rx(roll) * Ry(pitch) * Rz(yaw) for the default 'XYZ' assignment (the
%   matrix used by stew_inverse.m).  For another assignment (rpy_perm) the
%   angles rotate about the assigned axes in the same order: R = P R0 P'.
if nargin < 4 || isempty(axes), axes = 'XYZ'; end
TXrad = roll  * pi/180;
TYrad = pitch * pi/180;
TZrad = yaw   * pi/180;
R = [cos(TYrad)*cos(TZrad),                                  -cos(TYrad)*sin(TZrad),                                  sin(TYrad);
     sin(TXrad)*sin(TYrad)*cos(TZrad)+cos(TXrad)*sin(TZrad), -sin(TXrad)*sin(TYrad)*sin(TZrad)+cos(TXrad)*cos(TZrad), -sin(TXrad)*cos(TYrad);
    -cos(TXrad)*sin(TYrad)*cos(TZrad)+sin(TXrad)*sin(TZrad),  cos(TXrad)*sin(TYrad)*sin(TZrad)+sin(TXrad)*cos(TZrad),  cos(TXrad)*cos(TYrad)];
if ~strcmpi(axes, 'XYZ')
    P = rpy_perm(axes);
    R = P * R * P';
end
end
