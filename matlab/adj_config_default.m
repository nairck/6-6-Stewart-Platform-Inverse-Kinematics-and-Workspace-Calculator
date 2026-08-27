function cfg = adj_config_default(nOrigins)
%ADJ_CONFIG_DEFAULT  Incremental Adj. Table set-up: nothing ticked, all turns
%   1.0, three decimals.  masks: nOrigins x 6 logical (X, Y, Z, Roll, Pitch,
%   Yaw); turns: nOrigins x 6 [deg].
if nargin < 1, nOrigins = 1; end
cfg = struct('decimals', 3, 'masks', false(nOrigins, 6), 'turns', ones(nOrigins, 6));
end
