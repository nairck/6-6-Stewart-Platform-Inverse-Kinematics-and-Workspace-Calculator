function load_data()
%LOAD_DATA  Ensure formdata.txt exists and is valid, populate the GUI or close.
%
%   File layout (identical in the Python version):
%       <tag> = <value with exactly 3 decimals>   (76 lines, formdata_tags order)
%       calculator_name = '<name>'
%       rpy_axes = 'ZXY'                           (optional: which axis roll, pitch,
%                                                   yaw rotate about; default XYZ)
%       origin_1 = 'Origin 1', 0.000, 0.000, 0.000, 0.000, 0.000, 0.000  (optional block)
%       origin_k = '<name, 1-22 chars>', <dx>, <dy>, <dz>, <roll>, <pitch>, <yaw>
%       origin_active = k                          (1 <= k <= number of origin lines)
%       adj_decimals = 3                           (optional block: the Incremental
%       adj_k = 'XYZRPW', 1.0, 1.0, 1.0, 1.0, 1.0, 1.0   Adj. Table set-up per origin)
%   An origin is a frame: offset [mm] and orientation [deg] relative to
%   Origin 1.  The origin block and the rpy_axes line are only present when
%   they carry information; the number of origins is the number of origin_k
%   lines.  Values are stored exactly as displayed, i.e. in the frame of the
%   ACTIVE origin.
%
%   Numbers are written with exactly three decimals; when reading, any decimal
%   number is accepted on a value line (e.g. a hand-edited "1.0011109" or "5")
%   and rounded to three decimals.  Older layouts are read and converted
%   forward as well.  Whenever the file differs from the canonical layout it is
%   rewritten at start-up:
%     * values not at three decimals (rounded);
%     * the 69-tag layout with a single Base Z / Platform Z plane height and
%       three bench values (every joint receives the plane height, bench values
%       are dropped);
%     * an "origin_count = N" line ahead of the origin lines (ignored);
%     * origin lines with only the three offsets (orientation taken as zero).

    hMain = gcf;
    plotinfo = get(hMain,'UserData');
    fname = 'formdata.txt';
    [tags, default_values, legacy_tags] = formdata_tags();
    defaultName = 'Hexapod Inverse Kinematics and Workspace Solver';
    NAME_MAX = 22;
    origins = struct('name',{'Origin 1'},'dx',{0},'dy',{0},'dz',{0},'roll',{0},'pitch',{0},'yaw',{0});
    originActive = 1;
    rpyAxes = 'XYZ';

    N = numel(tags);
    totalLines = N + 1;  % plus calculator_name

    %--- 2) If missing, Create or Quit ---
    if ~isfile(fname)
        prompt = sprintf( ...
          'formdata.txt not found in:\n%s\n\nCreate default file and proceed, or Quit to supply your own?', pwd);
        choice = questdlg(prompt,'File Missing','Create','Quit','Create');
        if isempty(choice) || strcmp(choice,'Quit')
            delete(hMain); return;
        end
        write_numeric_file(fname, tags, default_values, defaultName);
    end

    %--- 3) Read lines ---
    fid = fopen(fname,'r');
    rawLines = {};
    t = fgetl(fid);
    while ischar(t)
        rawLines{end+1,1} = strtrim(t);
        t = fgetl(fid);
    end
    fclose(fid);

    %--- 4) Validate format & collect ---
    % Layout detection: the per-joint-Z layout has 'base1z = ...' on line 3,
    % the old plane-height layout has 'base2x = ...' there.
    isLegacy = numel(rawLines) >= 3 && strncmp(rawLines{3}, 'base2x = ', 9);
    if isLegacy
        useTags = legacy_tags;
    else
        useTags = tags;
    end
    Nuse = numel(useTags);
    totalUse = Nuse + 1;
    vals   = zeros(Nuse,1);
    errors = {};
    calcName = defaultName;
    needRewrite = isLegacy;
    rewriteWhy = {};
    if isLegacy
        rewriteWhy{end+1} = 'older layout converted forward (each joint has its own Z; bench values dropped)';
    end
    rounded = false;
    % a decimal number: optional sign, digits, optional fraction of any length,
    % optional exponent (written back as %.3f)
    NUM = '[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?';

    if numel(rawLines) < totalUse
        errors{end+1} = sprintf('Expected at least %d lines but found %d.', totalUse, numel(rawLines));
    end
    for ii = 1:min(Nuse,numel(rawLines))
        expected = sprintf('%s = -123.456', useTags{ii});
        pat = ['^' regexptranslate('escape', useTags{ii}) ' = (' NUM ')$'];
        tok = regexp(rawLines{ii}, pat, 'tokens');
        if isempty(tok)
            errors{end+1} = sprintf('Line %d: ''%s''  - Expected: ''%s''', ii, rawLines{ii}, expected);
        else
            v = str2double(tok{1}{1});
            if isnan(v) || ~isfinite(v)
                errors{end+1} = sprintf('Line %d: non-numeric ''%s''', ii, rawLines{ii});
            else
                v = round(v, 3);
                if ~strcmp(sprintf('%.3f', v), tok{1}{1}), rounded = true; end
                vals(ii) = v;
            end
        end
    end
    if numel(rawLines) >= Nuse+1
        line = rawLines{Nuse+1};
        tok = regexp(line, '^calculator_name = ''(.{1,100})''$', 'tokens');
        if isempty(tok)
            errors{end+1} = sprintf('Line %d: ''%s''  - Expected: "calculator_name = ''...''"', Nuse+1, line);
        else
            calcName = tok{1}{1};
        end
    end

    % Optional origin block: origin_1..origin_N then origin_active = k.  An
    % older "origin_count = N" line ahead of them is accepted and ignored.
    idx = totalUse + 1;
    % optional rotation-angle axes line
    if idx <= numel(rawLines) && strncmp(rawLines{idx}, 'rpy_axes', 8)
        tok = regexp(rawLines{idx}, '^rpy_axes = ''([A-Za-z]{3})''$', 'tokens');
        if isempty(tok) || ~any(strcmp(upper(tok{1}{1}), {'XYZ','YZX','ZXY'}))
            errors{end+1} = sprintf('Line %d: ''%s''  - Expected: "rpy_axes = ''XYZ''" (XYZ, YZX or ZXY)', idx, rawLines{idx});
        else
            rpyAxes = upper(tok{1}{1});
            if ~strcmp(tok{1}{1}, rpyAxes) || strcmp(rpyAxes, 'XYZ')
                needRewrite = true;
                rewriteWhy{end+1} = 'rpy_axes line normalised';
            end
        end
        idx = idx + 1;
    end
    if idx <= numel(rawLines) && ~isempty(regexp(rawLines{idx}, '^origin_count = \d+$', 'once'))
        needRewrite = true;
        rewriteWhy{end+1} = 'origin_count line dropped (the number of origins is the number of origin lines)';
        idx = idx + 1;
    end
    parsed = struct('name',{},'dx',{},'dy',{},'dz',{},'roll',{},'pitch',{},'yaw',{});
    patO = ['^origin_(\d+) = ''([^'']{1,' num2str(NAME_MAX) '})'', (' NUM '), (' NUM '), (' NUM ')(?:, (' NUM '), (' NUM '), (' NUM '))?$'];
    shortOrigin = false;
    while idx <= numel(rawLines) && strncmp(rawLines{idx}, 'origin_', 7) && ~strncmp(rawLines{idx}, 'origin_active', 13)
        tok = regexp(rawLines{idx}, patO, 'tokens');
        if isempty(tok) || str2double(tok{1}{1}) ~= numel(parsed) + 1
            errors{end+1} = sprintf('Line %d: ''%s''  - Expected: "origin_%d = ''Name'', 0.000, 0.000, 0.000, 0.000, 0.000, 0.000"', ...
                                    idx, rawLines{idx}, numel(parsed) + 1);
            idx = idx + 1;
            continue;
        end
        t = tok{1};
        vals6 = zeros(1, 6);
        nGiven = 3;
        if numel(t) >= 8 && ~isempty(t{6}), nGiven = 6; else, shortOrigin = true; end
        for k = 1:nGiven
            vals6(k) = round(str2double(t{2+k}), 3);
            if ~strcmp(sprintf('%.3f', vals6(k)), t{2+k}), rounded = true; end
        end
        parsed(end+1) = struct('name', t{2}, 'dx', vals6(1), 'dy', vals6(2), 'dz', vals6(3), ...
                               'roll', vals6(4), 'pitch', vals6(5), 'yaw', vals6(6));
        idx = idx + 1;
    end
    if ~isempty(parsed)
        if idx <= numel(rawLines)
            tok = regexp(rawLines{idx}, '^origin_active = (\d+)$', 'tokens');
            if isempty(tok) || str2double(tok{1}{1}) < 1 || str2double(tok{1}{1}) > numel(parsed)
                errors{end+1} = sprintf('Line %d: ''%s''  - Expected: ''origin_active = 1'' (1..%d)', ...
                                        idx, rawLines{idx}, numel(parsed));
            else
                originActive = str2double(tok{1}{1});
            end
            idx = idx + 1;
        else
            errors{end+1} = sprintf('Line %d: missing ''origin_active = k'' after the origin lines.', idx);
        end
        if any([parsed(1).dx, parsed(1).dy, parsed(1).dz, parsed(1).roll, parsed(1).pitch, parsed(1).yaw] ~= 0)
            errors{end+1} = sprintf('Line %d: Origin 1 must have a zero offset and orientation (it is the reference origin).', totalUse+1);
        end
        if shortOrigin
            needRewrite = true;
            rewriteWhy{end+1} = 'origin lines without an orientation (roll, pitch, yaw taken as 0)';
        end
        origins = parsed;
    end
    % optional Incremental Adj. Table block: adj_decimals then adj_1 .. adj_N
    adjCfg = adj_config_default(numel(origins));
    if idx <= numel(rawLines) && strncmp(rawLines{idx}, 'adj_', 4)
        tok = regexp(rawLines{idx}, '^adj_decimals = (\d)$', 'tokens');
        if isempty(tok)
            errors{end+1} = sprintf('Line %d: ''%s''  - Expected: ''adj_decimals = 3''', idx, rawLines{idx});
        else
            adjCfg.decimals = str2double(tok{1}{1});
        end
        idx = idx + 1;
        % Only the head of an adj_k line is matched strictly.  What follows is
        % read leniently: the quoted items are the labels (a label may hold any
        % character except a quote, which is why they are not part of the
        % pattern), and the six numbers left after removing them are the turns.
        % A label can therefore never make a settings file look corrupt.
        patA = '^adj_(\d+) = ''([XYZRPW\-]{6})''(.*)$';
        k = 0;
        while idx <= numel(rawLines) && strncmp(rawLines{idx}, 'adj_', 4)
            tok = regexp(rawLines{idx}, patA, 'tokens', 'once');
            if numel(tok) == 3
                labs = regexp(tok{3}, '''([^'']*)''', 'tokens');
                nums = regexp(regexprep(tok{3}, '''[^'']*''', ''), '[-+]?\d*\.?\d+', 'match');
            else
                labs = {};  nums = {};
            end
            if isempty(tok) || str2double(tok{1}) ~= k + 1 || numel(nums) < 6
                errors{end+1} = sprintf('Line %d: ''%s''  - Expected: "adj_%d = ''XYZRPW'', 1.0, 1.0, 1.0, 1.0, 1.0, 1.0"', idx, rawLines{idx}, k + 1);
                idx = idx + 1;
                continue;
            end
            if k < numel(origins)
                adjCfg.masks(k+1, :) = tok{2} ~= '-';
                for j = 1:6, adjCfg.turns(k+1, j) = round(str2double(nums{j}), 1); end
                for j = 1:min(numel(labs), 6)
                    adjCfg.labels{k+1, j} = labs{j}{1};
                end
            else
                needRewrite = true;
                rewriteWhy{end+1} = 'adj_k lines beyond the number of origins dropped';
            end
            k = k + 1;
            idx = idx + 1;
        end
        if k < numel(origins)
            needRewrite = true;
            rewriteWhy{end+1} = 'adj_k lines missing for some origins (nothing ticked for them)';
        end
    end
    if idx <= numel(rawLines)
        errors{end+1} = sprintf('Line %d: ''%s''  - Unexpected extra line (only rpy_axes / origin_k / origin_active / adj_k lines may follow calculator_name).', ...
                                idx, rawLines{idx});
    end

    %--- 5) If errors, preview up to 4, Overwrite/Quit ---
    if ~isempty(errors)
        previewCount = min(4,numel(errors));
        txt = strjoin(errors(1:previewCount), '\n');
        if numel(errors)>previewCount
            txt = [txt sprintf('\n...and %d more invalid lines', numel(errors)-previewCount)];
        end
        msg = sprintf(['Invalid formdata.txt detected.\n' ...
                       'Issues (expected "tag = -123.456" or valid name):\n\n%s\n\n' ...
                       'Overwrite with defaults or Quit to fix?'], txt);
        choice = questdlg(msg,'Corrupted Formdata','Overwrite','Quit','Quit');
        if isempty(choice) || strcmp(choice,'Quit')
            delete(hMain); return;
        end
        write_numeric_file(fname, tags, default_values, defaultName);
        vals = default_values(:);
        useTags = tags;
        calcName = defaultName;
        origins = struct('name',{'Origin 1'},'dx',{0},'dy',{0},'dz',{0},'roll',{0},'pitch',{0},'yaw',{0});
        originActive = 1;
        rpyAxes = 'XYZ';
        adjCfg = adj_config_default(1);
        isLegacy = false;
        needRewrite = false;
    end
    if originActive < 1 || originActive > numel(origins)
        originActive = 1;
    end
    if rounded && isempty(errors)
        needRewrite = true;
        rewriteWhy{end+1} = 'values rounded to three decimals';
    end

    %--- 6) Convert a legacy (plane-height) file forward ---
    % base{i}z <- baseZ, plat{i}z <- platZheight; bench values dropped.
    valmap = containers.Map(useTags, num2cell(vals(:)'));
    if isLegacy
        for i = 1:6
            valmap(sprintf('base%dz', i)) = valmap('baseZ');
            valmap(sprintf('plat%dz', i)) = valmap('platZheight');
        end
    end

    %--- 7) Populate GUI numeric fields ---
    for ii=1:N
        set(plotinfo.(tags{ii}), 'String', num2str(valmap(tags{ii}),'%.3f'));
    end

    %--- 8) Apply calculator_name and origins ---
    plotinfo.calculator_name = calcName;
    set(hMain,'Name',calcName);
    plotinfo.origins = origins;
    plotinfo.origin_active = originActive;
    plotinfo.rpy_axes = rpyAxes;
    plotinfo.adj_config = adj_config_normalise(adjCfg, numel(origins));

    set(hMain,'UserData',plotinfo);
    refresh_origin_ui(hMain);   % "Current Origin" button label + Edit-ZPD lock
    refresh_angle_labels(hMain);
    if numel(origins) > 1 || originActive ~= 1
        fprintf('Origins loaded: %d; active origin: %s (X %.3f, Y %.3f, Z %.3f mm from Origin 1).\n', ...
            numel(origins), origins(originActive).name, origins(originActive).dx, ...
            origins(originActive).dy, origins(originActive).dz);
    end

    %--- 9) Rewrite an older layout in the current one ---
    if needRewrite
        set(0, 'CurrentFigure', hMain);
        save_data();
        fprintf('''%s'' rewritten in the current format (%s).\n', fname, strjoin(rewriteWhy, '; '));
    end

    %--- 10) Recompute deltas & refresh visuals ---
    oldR = str2double(get(plotinfo.roll_old,'String'));
    newR = str2double(get(plotinfo.roll,'String'));
    if oldR == newR
        zero_data();
    else
        prim = {'roll','pitch','yaw','Pxval','Pyval','Pzval'};
        for k = 1:numel(prim)
            prev = str2double(get(plotinfo.([prim{k} '_old']),'String'));
            curr = str2double(get(plotinfo.(prim{k}),'String'));
            set(plotinfo.([prim{k} 'delta']), 'String', num2str(curr-prev,'%.3f'));
        end
    end

    zpd = str2double(get(plotinfo.zpdLegLength,'String'));
    for j = 1:6
        prevL = str2double(get(plotinfo.(sprintf('leg%d_old',j)),'String'));
        currL = str2double(get(plotinfo.(sprintf('leg%d',j)),'String'));
        set(plotinfo.(sprintf('leg%ddelta',j)),    'String', num2str(currL-prevL,'%.3f'));
        set(plotinfo.(sprintf('leg%dabsdelta',j)), 'String', num2str(currL-zpd,   '%.3f'));
        ang = (currL-prevL) * 360 / str2double(get(plotinfo.actuatorLead,'String'));
        set(plotinfo.(sprintf('leg%dangledelta',j)),'String',num2str(ang,'%.3f'));
    end

    color_input_box();
end


function write_numeric_file(fname, tags, values, name)
    fid = fopen(fname,'w');
    for ii=1:numel(tags)
        fprintf(fid,'%s = %.3f\n', tags{ii}, values(ii));
    end
    fprintf(fid, 'calculator_name = ''%s''\n', name);
    fclose(fid);
end
