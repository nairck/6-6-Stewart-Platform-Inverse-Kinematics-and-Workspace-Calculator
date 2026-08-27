function [px2, py2, pz2] = shift_frame(e, roll, pitch, yaw, px, py, pz)
%SHIFT_FRAME  Re-express a pose when the coordinate origin is moved by -e.
%
%   Every joint coordinate is translated by e (a_i' = a_i + e, b_i' = b_i + e),
%   which places the new point of interest at the origin. For the platform to
%   stay physically where it is, the leg vectors must be unchanged:
%
%       a_i' - (R b_i' + p') = a_i - (R b_i + p)
%       (a_i + e) - R b_i - R e - p' = a_i - R b_i - p
%       p' = p + e - R e
%
%   The rotation R (roll, pitch, yaw) is identical in both frames; only the
%   translation changes. Home (R = I, p = 0) maps to home in every frame.
%
%   e          : 1x3 shift applied to the joint coordinates (old_offset - new_offset)
%   roll..yaw  : pose angles [deg] (same convention as stew_inverse.m)
%   px, py, pz : translation in the current frame
%   Returns the translation in the shifted frame.

TXrad = roll  * pi/180;
TYrad = pitch * pi/180;
TZrad = yaw   * pi/180;
% identical rotation block to stew_inverse.m
R = [cos(TYrad)*cos(TZrad),                                  -cos(TYrad)*sin(TZrad),                                  sin(TYrad);
     sin(TXrad)*sin(TYrad)*cos(TZrad)+cos(TXrad)*sin(TZrad), -sin(TXrad)*sin(TYrad)*sin(TZrad)+cos(TXrad)*cos(TZrad), -sin(TXrad)*cos(TYrad);
    -cos(TXrad)*sin(TYrad)*cos(TZrad)+sin(TXrad)*sin(TZrad),  cos(TXrad)*sin(TYrad)*sin(TZrad)+sin(TXrad)*cos(TZrad),  cos(TXrad)*cos(TYrad)];
e = e(:);
p2 = [px; py; pz] + e - R*e;
px2 = p2(1);
py2 = p2(2);
pz2 = p2(3);
end
