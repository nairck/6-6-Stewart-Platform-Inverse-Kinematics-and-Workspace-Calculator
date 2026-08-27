function D = dataset_view_frame(fname)
%DATASET_VIEW_FRAME  The 3 x 3 view frame stored in a workspace .mat file
%   (identity for files without one or with an invalid one).
D = eye(3);
if ~isfile(fname), return; end
try
    s = load(fname, 'view_frame');
    if isfield(s, 'view_frame')
        V = reshape(double(s.view_frame), 3, 3);
        if all(isfinite(V(:))) && abs(det(V) - 1) < 1e-6
            D = V;
        end
    end
catch
end
end
