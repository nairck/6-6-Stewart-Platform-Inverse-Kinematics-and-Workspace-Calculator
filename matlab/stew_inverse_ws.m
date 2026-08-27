function Legs = stew_inverse_ws(xsi, ysi, zsi, xmi, ymi, zmi, roll, pitch, yaw, px, py, pz, axes)
%#codegen
% Optimized inverse kinematics function for a hexapod.  Every base joint
% (xsi, ysi, zsi) and platform joint (xmi, ymi, zmi) has its own X, Y, Z: no
% plane assumption.  (The codegen/ folder and the .mexw64 shipped in this repo
% were generated for the previous baseZ/platformZ signature and are not called
% by the program; regenerate them with the line below if you want a MEX build.)
% CALL THIS ONCE TO COMPILE MEX FILE AND CODEGEN FOLDER FROM SCRATCH:
%       codegen stew_inverse_ws -args {zeros(6,1), zeros(6,1), zeros(6,1), zeros(6,1), zeros(6,1), zeros(6,1), 0, 0, 0, 0, 0, 0}
% axes (optional, default 'XYZ'): which axis roll / pitch / yaw rotate about
% (rpy_perm.m); R = P R0 P' with R0 the Rx Ry Rz matrix.
if nargin < 13 || isempty(axes), axes = 'XYZ'; end
% Precompute sin/cos
TXrad = roll * pi/180;
TYrad = pitch * pi/180;
TZrad = yaw * pi/180;
cTX = cos(TXrad); sTX = sin(TXrad);
cTY = cos(TYrad); sTY = sin(TYrad);
cTZ = cos(TZrad); sTZ = sin(TZrad);
R = [cTY*cTZ,            -cTY*sTZ,           sTY;
     sTX*sTY*cTZ+cTX*sTZ, -sTX*sTY*sTZ+cTX*cTZ, -sTX*cTY;
    -cTX*sTY*cTZ+sTX*sTZ,  cTX*sTY*sTZ+sTX*cTZ,  cTX*cTY];
if ~strcmpi(axes, 'XYZ')
    P = rpy_perm(axes);
    R = P * R * P';
end
% Transformation matrix (only top 3 rows needed)
T = [R, [px; py; pz]];
% Base points (6x3) [x, y, z]
a = [xsi(:), ysi(:), zsi(:)];
% Platform points (6x3) [x, y, z]
b = [xmi(:), ymi(:), zmi(:)];
% Apply transformation
b_trans = (T(1:3,1:3) * b.' + T(1:3,4)).';
% Compute leg lengths
diff = a - b_trans;
Legs = sqrt(sum(diff.^2, 2));
