function M = axis_map_matrix(mapX, mapY, mapZ)
%AXIS_MAP_MATRIX  Signed permutation matrix for a relabelling of the axes.
%   mapX is the signed new axis that the CURRENT X axis becomes ('+X', '-X',
%   '+Y', '-Y', '+Z' or '-Z'); mapY / mapZ likewise for the current Y and Z.
%   A vector with current coordinates v has new coordinates M*v; the columns
%   of M are the mapped axis vectors.  The combination must be right-handed
%   (det M = +1, i.e. mapZ = mapX x mapY); an error is raised otherwise.
cx = axis_vector(mapX);
cy = axis_vector(mapY);
cz = axis_vector(mapZ);
M = [cx(:), cy(:), cz(:)];
if abs(det(M) - 1) > 1e-9 || any(abs(cross(cx, cy) - cz) > 1e-12)
    error('axis_map_matrix:notRightHanded', 'axis mapping is not a right-handed relabelling');
end
end
