function D = standard_display_frame(basePts, platPts)
%STANDARD_DISPLAY_FRAME  The sketch's display frame D (display = D * p) from
%   the geometry itself, so the default view looks natural whatever the
%   coordinate axes are (identical rule to the Python version):
%     * screen up is the normal of the plane the joints lie in (least
%       variance direction of all twelve joints), oriented from the base
%       centroid towards the platform centroid (base below platform);
%     * screen range (display X, left to right) is the direction of greatest
%       joint extent within that plane, its sign chosen so the mechanism lies
%       on its positive side (the triad points downrange, towards it);
%     * the third axis completes a right-handed set.
%   basePts, platPts : 3 x 6.  Degenerate inputs give eye(3).
D = eye(3);
P = [basePts, platPts];                       % 3 x 12
if ~isequal(size(P), [3 12]) || ~all(isfinite(P(:))), return; end
cAll = mean(P, 2);
Q = P - cAll;
scale = max(abs(Q(:)));  if scale == 0, return; end
[U, S, ~] = svd(Q / scale, 'econ');           % columns of U: principal directions
sing = diag(S);
if sing(1) < 1e-9 || sing(2) < 1e-9 * sing(1), return; end
up = U(:,3)';
sep = (mean(platPts, 2) - mean(basePts, 2))';
if dot(up, sep) < 0, up = -up; end
rng = U(:,1)' - dot(U(:,1)', up) * up;
n = norm(rng);  if n < 1e-9, return; end
rng = rng / n;
proj = dot(cAll', rng);
if abs(proj) > 1e-6 * scale
    if proj < 0, rng = -rng; end
else
    [~, k] = max(abs(rng));
    if rng(k) < 0, rng = -rng; end
end
side = cross(up, rng);
D = [rng; side; up];
if det(D) < 0, D(2,:) = -D(2,:); end
end
