function sig = state_signature(mainFig)
%STATE_SIGNATURE  One string describing everything Save Everything writes.
%   The 3-decimal strings that are actually saved, the origin list and the
%   active origin.  Equal signatures mean the file on disk already holds the
%   current state, so Quit / Escape / the close button need not ask.
    pinfo = get(mainFig, 'UserData');
    tags = formdata_tags();
    parts = cell(1, numel(tags));
    for i = 1:numel(tags)
        parts{i} = sprintf('%.3f', str2double(get(pinfo.(tags{i}), 'String')));
    end
    if isfield(pinfo, 'origins')
        for i = 1:numel(pinfo.origins)
            o = pinfo.origins(i);
            [Ro, dO] = origin_frame(o);                 %#ok<ASGLU>
            ang = zeros(1,3);
            names = {'roll', 'pitch', 'yaw'};
            for k = 1:3
                if isfield(o, names{k}) && ~isempty(o.(names{k})), ang(k) = o.(names{k}); end
            end
            parts{end+1} = sprintf('%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f', o.name, dO(1), dO(2), dO(3), ang(1), ang(2), ang(3));
        end
        parts{end+1} = sprintf('active=%d', pinfo.origin_active);
    end
    if isfield(pinfo, 'calculator_name')
        parts{end+1} = pinfo.calculator_name;
    end
    parts{end+1} = ['rpy=' rpy_axes_of(pinfo)];
    if isfield(pinfo, 'adj_config')
        cfg = adj_config_normalise(pinfo.adj_config, numel(pinfo.origins));
        parts{end+1} = sprintf('adj=%d|%s|%s', cfg.decimals, mat2str(cfg.masks), mat2str(cfg.turns));
    end
    sig = strjoin(parts, ';');
end
