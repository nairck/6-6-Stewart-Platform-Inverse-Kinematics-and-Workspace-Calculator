function cfg = adj_config_normalise(cfg, nOrigins)
%ADJ_CONFIG_NORMALISE  One row per origin (truncate or pad), turns rounded to
%   one decimal, decimals in 0..6.
def = adj_config_default(nOrigins);
if isempty(cfg) || ~isstruct(cfg), cfg = def; end
if ~isfield(cfg, 'decimals') || isempty(cfg.decimals) || isnan(cfg.decimals), cfg.decimals = 3; end
cfg.decimals = min(max(round(cfg.decimals), 0), 6);
for f = {'masks', 'turns'}
    if ~isfield(cfg, f{1}) || isempty(cfg.(f{1})), cfg.(f{1}) = def.(f{1}); end
    v = cfg.(f{1});
    n = size(v, 1);
    if n < nOrigins
        v = [v; def.(f{1})(n+1:end, :)];
    elseif n > nOrigins
        v = v(1:nOrigins, :);
    end
    cfg.(f{1}) = v;
end
cfg.masks = logical(cfg.masks);
cfg.turns = round(double(cfg.turns), 1);
cfg.turns(~isfinite(cfg.turns)) = 1;
end
