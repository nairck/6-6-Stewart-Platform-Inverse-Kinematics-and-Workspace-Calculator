function save_data()
%SAVE_DATA  Write every numeric field, calculator_name and the origins to formdata.txt.
% If unable to open formdata.txt, falls back to creating formdata_new.txt.
% Also records the saved state (see state_signature.m) so Quit / Escape / the
% window close button can tell whether anything changed since.

    plotinfo = get(gcf,'UserData');
    fname = 'formdata.txt';
    tags = formdata_tags();

    % Try to open the primary file
    fid = fopen(fname,'w');
    if fid < 0
        % Fallback to a new file
        fallback = 'formdata_new.txt';
        fid = fopen(fallback,'w');
        if fid < 0
            error('Unable to open %s for writing.', fallback);
        end
    end

    % Write numeric tags with three decimals
    for i = 1:numel(tags)
        tag = tags{i};
        val = str2double(get(plotinfo.(tag),'String'));
        fprintf(fid, '%s = %.3f\n', tag, val);
    end

    % Write calculator_name (as loaded at startup)
    fprintf(fid, 'calculator_name = ''%s''\n', plotinfo.calculator_name);

    % Rotation-angle axes assignment, only when not the default
    axes = rpy_axes_of(plotinfo);
    if ~strcmp(axes, 'XYZ')
        fprintf(fid, 'rpy_axes = ''%s''\n', axes);
    end

    % Origins / points of interest: written only when the block carries
    % information (more than one origin, a non-default active origin, or
    % Origin 1 renamed).  The number of origins is the number of lines.
    if isfield(plotinfo, 'origins') && isfield(plotinfo, 'origin_active')
        origins = plotinfo.origins;
        active  = plotinfo.origin_active;
        if numel(origins) > 1 || active ~= 1 || ~strcmp(origins(1).name, 'Origin 1')
            for i = 1:numel(origins)
                [~, dO] = origin_frame(origins(i));
                fprintf(fid, 'origin_%d = ''%s'', %.3f, %.3f, %.3f, %.3f, %.3f, %.3f\n', i, origins(i).name, ...
                        dO(1), dO(2), dO(3), origin_angle(origins(i), 'roll'), ...
                        origin_angle(origins(i), 'pitch'), origin_angle(origins(i), 'yaw'));
            end
            fprintf(fid, 'origin_active = %d\n', active);
        end
    end

    % Incremental Adj. Table set-up, only when it carries information
    if isfield(plotinfo, 'adj_config')
        cfg = adj_config_normalise(plotinfo.adj_config, numel(plotinfo.origins));
        if ~adj_config_is_default(cfg)
            fprintf(fid, 'adj_decimals = %d\n', cfg.decimals);
            letters = 'XYZRPW';
            for i = 1:size(cfg.masks, 1)
                mask = repmat('-', 1, 6);
                mask(cfg.masks(i, :)) = letters(cfg.masks(i, :));
                line = sprintf('adj_%d = ''%s'', %.1f, %.1f, %.1f, %.1f, %.1f, %.1f', ...
                               i, mask, cfg.turns(i, :));
                if any(~cellfun(@isempty, cfg.labels(i, :)))   % the labels, when some were typed
                    for j = 1:6
                        line = [line sprintf(', ''%s''', cfg.labels{i, j})]; %#ok<AGROW>
                    end
                end
                fprintf(fid, '%s\n', line);
            end
        end
    end

    fclose(fid);

    plotinfo.saved_signature = state_signature(gcf);
    set(gcf, 'UserData', plotinfo);
end


function v = origin_angle(o, name)
if isfield(o, name) && ~isempty(o.(name))
    v = o.(name);
else
    v = 0;
end
end
