function tf = adj_config_is_default(cfg)
tf = cfg.decimals == 3 && ~any(cfg.masks(:)) && all(cfg.turns(:) == 1);
end
