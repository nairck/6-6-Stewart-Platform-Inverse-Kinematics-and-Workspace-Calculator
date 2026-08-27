function frame_view(ax, az, el, D)
%FRAME_VIEW  view(az, el) expressed in the sketch's DISPLAY frame.
%   The viewing direction and the up vector that view(az, el) would use (+Z
%   up) are given in display coordinates and converted to the data axes with
%   the dataset's view frame D (display = D * data, so data = D' * display),
%   so after a Change Coords. or a rotated origin the 3D windows keep the
%   sketch's "up".  D = eye(3) reproduces view(az, el) exactly.
if nargin < 4 || isempty(D), D = eye(3); end
d  = [sind(az)*cosd(el), -cosd(az)*cosd(el), sind(el)];   % MATLAB view(az,el) line of sight
up = [0 0 1];
dData  = (D' * d(:))';
upData = (D' * up(:))';
view(ax, dData);
camup(ax, upData);
end
