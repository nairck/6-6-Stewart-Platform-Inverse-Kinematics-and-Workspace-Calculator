function incremental_adj_table(mainFig)
%INCREMENTAL_ADJ_TABLE  Modal window: per-origin, per-axis leg ratio table
%   (see incremental_adj_rows.m for the maths; identical to the Python
%   IncrementalAdjDialog).
%
%   Top: one row per origin with a check box for each of X, Y, Z, Roll,
%   Pitch, Yaw.  Then, right-justified, the number of decimal places.  Then
%   the table: one row per ticked (origin, axis) in X, Y, Z, Roll, Pitch, Yaw
%   order within each origin, origins in list order; the origin name is shown
%   once per group (wrapped once after 7 characters), the axis with a + sign,
%   the editable 'Turn [deg]' (the manual turn given to the reference leg,
%   default 1.0, one decimal, positive or negative) and the six leg entries
%   = unit ratio x turn, every entry that reads +1 or -1 at the chosen
%   decimals in bold.  "Round up above 0.99" (on by default, not saved) takes
%   any unit ratio whose rounded magnitude exceeds 0.99 to exactly 1.  Bold
%   marks the legs whose unit ratio reads +/-1, decided at turn = 1.0 and kept
%   as the turns change.  "Reset turns" puts every turn back to 1.0.  Export
%   writes the table as text, Excel (live formulas) or PNG.  Confirm keeps
%   the set-up (ticks, turns, decimals) in the program (saved by Save
%   Everything); Close discards the changes.

pinfo = get(mainFig, 'UserData');
origins = pinfo.origins;
nO = numel(origins);
cfg = adj_config_normalise(pinfo.adj_config, nO);
anyTicks = any(cfg.masks(:));
AXES = {'X', 'Y', 'Z', 'Roll', 'Pitch', 'Yaw'};
W = 760;  M = 15;  ROW_H = 24;  GAP = 8;  BTN_H = 28;
hIntro = 52;  hHdr = 18;  hDec = 24;
tableRows = 8;                         % visible rows before the uitable scrolls
hTable = hHdr + tableRows * ROW_H + 8;
H = M + hIntro + GAP + hHdr + nO * ROW_H + GAP + hDec + GAP + hTable + GAP + BTN_H + M;

d = dialog('Name', 'Incremental Adjustment Table', 'WindowStyle', 'modal', ...
           'Resize', 'off', 'Visible', 'off', 'Position', [0 0 W H]);
movegui(d, 'center');
bg = get(d, 'Color');
setappdata(d, 'mainFig', mainFig);

y = H - M - hIntro;
uicontrol(d, 'Style', 'text', 'Position', [M y W-2*M hIntro], 'FontSize', 9, ...
    'HorizontalAlignment', 'left', 'BackgroundColor', bg, 'String', ...
    {'Tick the axes to tabulate. Leg entry = unit ratio x Turn [deg]: the actuator turn of each leg for a small move'; ...
     'in the + direction of the row''s axis of that origin''s frame (sign gives the direction of turn: positive'; ...
     'extends the leg, negative retracts it).'});

% --- selection grid ---
y = y - GAP - hHdr;
gridW = 150 + 14 + 6 * 66;                   % names column + gap + six tick columns
gx = round((W - gridW) / 3);                 % one part of the free space left of the grid, two parts right
colX = gx + 150 + 14 + (0:5) * 66;
uicontrol(d, 'Style', 'text', 'Position', [gx y 150 hHdr], 'String', 'Origin', 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'BackgroundColor', bg);
for c = 1:6
    uicontrol(d, 'Style', 'text', 'Position', [colX(c)-20 y 60 hHdr], 'String', AXES{c}, ...
        'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'BackgroundColor', bg);
end
checks = gobjects(nO, 6);
for i = 1:nO
    y = y - ROW_H;
    uicontrol(d, 'Style', 'text', 'Position', [gx y+3 150 hHdr], 'String', origins(i).name, ...
        'HorizontalAlignment', 'center', 'BackgroundColor', bg);
    for c = 1:6
        if anyTicks, on = cfg.masks(i, c); else, on = (i == pinfo.origin_active); end
        checks(i, c) = uicontrol(d, 'Style', 'checkbox', 'Position', [colX(c) y+2 20 20], ...
            'Value', double(on), 'BackgroundColor', bg, ...
            'Callback', @(~, ~) refresh(d));
    end
end
setappdata(d, 'checks', checks);

% --- the row above the table: "Decimal places" flush with the table's left
% edge, "Round up above 0.99" (the tick after its label) flush with its right
% edge; tableX / tableW are the same values the table itself uses below ---
y = y - GAP - hDec;
tableW = 118 + 56 + 6 * 70 + 72 + 4;
tableX = round((W - tableW) / 2);
tipRound = 'Show a unit ratio whose rounded magnitude is above 0.99 as exactly 1 (and mark that leg bold)';
uicontrol(d, 'Style', 'text', 'Position', [tableX y+2 110 hDec-4], 'String', 'Decimal places:', ...
    'HorizontalAlignment', 'left', 'BackgroundColor', bg);
hDecPop = uicontrol(d, 'Style', 'popupmenu', 'Position', [tableX+112 y 64 hDec], ...
    'String', {'0','1','2','3','4','5','6'}, 'Value', cfg.decimals + 1, 'Callback', @(~, ~) refresh(d));
setappdata(d, 'decPop', hDecPop);
boxW = 18;  labW = 128;                    % label then tick, ending at the table's right edge
uicontrol(d, 'Style', 'text', 'Position', [tableX+tableW-boxW-labW y+2 labW hDec-4], ...
    'String', 'Round up above 0.99', 'HorizontalAlignment', 'right', 'BackgroundColor', bg, ...
    'TooltipString', tipRound);
hRound = uicontrol(d, 'Style', 'checkbox', 'Position', [tableX+tableW-boxW y+3 boxW hDec-6], ...
    'String', '', 'Value', 1, 'BackgroundColor', bg, 'TooltipString', tipRound, ...
    'Callback', @(~, ~) refresh(d));
setappdata(d, 'roundPop', hRound);

% --- table ---
y = y - GAP - hTable;
hT = uitable(d, 'Position', [tableX y tableW hTable], ...   % centred (tableX / tableW above)
    'ColumnName', [{'Origin', 'Axis'}, arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false), {'Turn [deg]'}], ...
    'ColumnWidth', {118, 56, 70, 70, 70, 70, 70, 70, 72}, 'RowName', [], ...
    'ColumnEditable', [false false false false false false false false true], ...
    'ColumnFormat', repmat({'char'}, 1, 9), 'CellEditCallback', @(src, evt) turn_edited(d, evt));
setappdata(d, 'table', hT);
turns = containers.Map('KeyType', 'char', 'ValueType', 'double');
AXES6 = {'X', 'Y', 'Z', 'Roll', 'Pitch', 'Yaw'};
for i = 1:nO
    for c = 1:6
        if cfg.turns(i, c) ~= 1, turns(sprintf('%d|+%s', i, AXES6{c})) = cfg.turns(i, c); end
    end
end
setappdata(d, 'turns', turns);

y = y - GAP - BTN_H;
bx = W - M - 100;
confirmRight = bx - 8 - 100;               % left edge of Confirm, set below
uicontrol(d, 'Style', 'pushbutton', 'Position', [bx y 100 BTN_H], 'String', 'Close', ...
    'Callback', @(~, ~) delete(d));
bx = bx - 8 - 100;
uicontrol(d, 'Style', 'pushbutton', 'Position', [bx y 100 BTN_H], 'String', 'Confirm', ...
    'Callback', @(~, ~) on_confirm(d));
% export buttons left-aligned with the table's left edge, same 8 px gap
exports = {'.png', 'Export .PNG ...'; '.txt', 'Export .TXT ...'; '.xlsx', 'Export .XLSX ...'};
bx = tableX;
for i = 1:3
    uicontrol(d, 'Style', 'pushbutton', 'Position', [bx y 110 BTN_H], 'String', exports{i, 2}, ...
        'Callback', @(~, ~) export_table(d, exports{i, 1}));
    bx = bx + 110 + 8;
end
% "Reset turns" centred between the export block and Confirm
resetW = 110;
resetX = round(0.5 * (bx - 8 + confirmRight - resetW));
uicontrol(d, 'Style', 'pushbutton', 'Position', [resetX y resetW BTN_H], 'String', 'Reset turns', ...
    'TooltipString', 'Set every row''s turn back to 1.0', 'Callback', @(~, ~) reset_turns(d));

refresh(d);
set(d, 'Visible', 'on');
end


% =========================================================================
function sel = selections(d)
checks = getappdata(d, 'checks');
sel = false(size(checks));
for i = 1:numel(checks)
    sel(i) = logical(get(checks(i), 'Value'));
end
end


function dec = decimals(d)
p = getappdata(d, 'decPop');
dec = get(p, 'Value') - 1;
end


function tf = round_up(d)
h = getappdata(d, 'roundPop');
tf = ~isempty(h) && logical(get(h, 'Value'));
end


function on_confirm(d)
%ON_CONFIRM  Keep the set-up (ticks, turns, decimals) in the main figure.
mainFig = getappdata(d, 'mainFig');
pinfo = get(mainFig, 'UserData');
nO = numel(pinfo.origins);
cfg = adj_config_default(nO);
cfg.decimals = decimals(d);
cfg.masks = selections(d);
turns = getappdata(d, 'turns');
AXES6 = {'X', 'Y', 'Z', 'Roll', 'Pitch', 'Yaw'};
for i = 1:nO
    for c = 1:6
        key = sprintf('%d|+%s', i, AXES6{c});
        if isKey(turns, key), cfg.turns(i, c) = turns(key); end
    end
end
pinfo.adj_config = adj_config_normalise(cfg, nO);
set(mainFig, 'UserData', pinfo);
delete(d);
disp('incremental adjustment table set-up confirmed.');
end


function key = row_key(r)
key = sprintf('%d|%s', r.origin, r.axis);
end


function rows = with_turns(d, rows)
%WITH_TURNS  Attach to every row the turn multiplier (default 1.0), the unit
%   ratios as the table reads them (rounded to the chosen decimals, and with
%   "Round up above 0.99" any magnitude above 0.99 but below 1 taken to
%   exactly +/-1), the entries values = unit * turn, and the legs shown in
%   bold.  Bold is decided from the UNIT state (turn = 1.0) and therefore does
%   not change as the turns are edited (identical rule to adj_table.py).
turns = getappdata(d, 'turns');
dec = decimals(d);
snapUp = round_up(d);
for k = 1:numel(rows)
    key = row_key(rows(k));
    if isKey(turns, key), m = turns(key); else, m = 1.0; end
    rows(k).turn = max(-99999.9, min(99999.9, round(m, 1)));
    unit = round(rows(k).ratios, dec);
    if snapUp
        snap = abs(unit) > 0.99 & abs(unit) < 1;
        unit(snap) = sign(unit(snap));
    end
    rows(k).unit = unit;
    rows(k).values = unit * rows(k).turn;
    rows(k).bold = find(abs(abs(round(unit, dec)) - 1) < 1e-12);
end
end


function turn_edited(d, evt)
%TURN_EDITED  A Turn cell was edited: accept a number (positive or negative),
%   round to one decimal, and recompute that row's entries.
rows = getappdata(d, 'rows');
k = evt.Indices(1);
if evt.Indices(2) ~= 9 || k > numel(rows), return; end
raw = strtrim(char(evt.EditData));
v = str2double(strrep(raw, char(8722), '-'));
turns = getappdata(d, 'turns');
if isnan(v) || ~isfinite(v)
    % not a number: keep the previous value
    key = row_key(rows(k));
    if isKey(turns, key), v = turns(key); else, v = 1.0; end
end
turns(row_key(rows(k))) = max(-99999.9, min(99999.9, round(v, 1)));   % capped like the Python version
setappdata(d, 'turns', turns);
refresh(d);
end


function reset_turns(d)
setappdata(d, 'turns', containers.Map('KeyType', 'char', 'ValueType', 'double'));
refresh(d);
end


function refresh(d)
mainFig = getappdata(d, 'mainFig');
rows = with_turns(d, incremental_adj_rows(mainFig, selections(d)));
setappdata(d, 'rows', rows);
dec = decimals(d);
fmt = sprintf('%%.%df', dec);
% MATLAB's table cannot merge cells, so an origin's name is written on the
% middle row of its group (centred over the group by eye); a two-word name of
% a group with at least two rows is split over the two middle rows.
data = cell(numel(rows), 9);
nameRows = containers.Map('KeyType', 'double', 'ValueType', 'any');
groups = unique([rows.origin], 'stable');
for g = groups
    idx = find([rows.origin] == g);
    lines = {rows(idx(1)).name};
    if numel(idx) > 1
        w = wrap_origin_name(rows(idx(1)).name, 11);
        if numel(w) > 1 && numel(idx) >= 2, lines = w; end
    end
    mid = idx(1) + floor((numel(idx) - numel(lines)) / 2);
    for t = 1:numel(lines)
        nameRows(mid + t - 1) = lines{t};
    end
end
for k = 1:numel(rows)
    r = rows(k);
    if isKey(nameRows, k)
        data{k, 1} = ['<html><div style="text-align:center">' nameRows(k) '</div></html>'];
    else
        data{k, 1} = '';
    end
    data{k, 2} = ['<html><div style="text-align:center">' r.axis '</div></html>'];
    for j = 1:6
        txt = sprintf(fmt, r.values(j));
        if any(r.bold == j)
            txt = ['<html><b style="font-weight:900">' txt '</b></html>'];   % double bold
        end
        data{k, 2 + j} = txt;
    end
    data{k, 9} = sprintf('%.1f', r.turn);
end
set(getappdata(d, 'table'), 'Data', data);
end


function export_table(d, ext)
%EXPORT_TABLE  Export as ext (.png, .txt or .xlsx): one save dialog limited
%   to that type, starting in the last folder used anywhere in the program.
rows = getappdata(d, 'rows');
if isempty(rows)
    uiwait(msgbox('Tick at least one axis first.', 'Nothing to export', 'modal'));
    return;
end
filters = struct('png', {{'*.png', 'PNG image (*.png)'}}, 'txt', {{'*.txt', 'Text file (*.txt)'}}, ...
                 'xlsx', {{'*.xlsx', 'Excel workbook (*.xlsx)'}});
kind = ext(2:end);
[file, pathName] = uiputfile(filters.(kind), ...
    sprintf('Export incremental adjustment table as %s', upper(kind)), ...
    fullfile(last_save_dir(), ['incremental_adjustment_table' ext]));
if isequal(file, 0), return; end
path = fullfile(pathName, file);
[~, ~, gotExt] = fileparts(path);
if ~strcmpi(gotExt, ext), path = [path ext]; end
last_save_dir(path);
mainFig = getappdata(d, 'mainFig');
pinfo = get(mainFig, 'UserData');
dec = decimals(d);
head = header_lines(pinfo, dec);
previews = origin_previews(pinfo, rows);
try
    switch lower(ext)
        case '.txt'
            fid = fopen(path, 'w');  fprintf(fid, '%s', table_text(rows, dec, head));  fclose(fid);
        case '.xlsx'
            export_xlsx(path, rows, dec, head, previews);
        otherwise
            export_png(path, rows, dec, head, previews);
    end
catch err
    uiwait(errordlg(sprintf('Export failed: %s', err.message), 'Export failed', 'modal'));
    return;
end
fprintf('incremental adjustment table exported to %s\n', path);
end


function previews = origin_previews(pinfo, rows)
%ORIGIN_PREVIEWS  For the first (at most two) origins in the table: the name
%   and the joints expressed in that origin's frame (q_1 = R_A q_A + d_A,
%   then q_o = R_o' (q_1 - d_o)), 3 x 6 each, for the previews in the exports.
getVal = @(f) str2double(get(pinfo.(f), 'String'));
axesRpy = rpy_axes_of(pinfo);
[R_A, d_A] = origin_frame(pinfo.origins(pinfo.origin_active), axesRpy);
base1 = zeros(3, 6);  plat1 = zeros(3, 6);
for i = 1:6
    base1(:, i) = R_A * [getVal(sprintf('base%dx',i)); getVal(sprintf('base%dy',i)); getVal(sprintf('base%dz',i))] + d_A;
    plat1(:, i) = R_A * [getVal(sprintf('plat%dx',i)); getVal(sprintf('plat%dy',i)); getVal(sprintf('plat%dz',i))] + d_A;
end
seen = unique([rows.origin], 'stable');
seen = seen(1:min(2, numel(seen)));
D1 = diag([-1 -1 1]) * standard_display_frame(base1, plat1);   % the primary origin's standard frame
previews = struct('name', {}, 'base', {}, 'plat', {}, 'frame', {});
for oi = seen
    [R_o, d_o] = origin_frame(pinfo.origins(oi), axesRpy);
    previews(end+1) = struct('name', pinfo.origins(oi).name, ...
        'base', R_o' * (base1 - d_o), 'plat', R_o' * (plat1 - d_o), 'frame', D1 * R_o); %#ok<AGROW>
end
end


function head = header_lines(pinfo, dec)
axes = rpy_axes_of(pinfo);
head = { 'Incremental Adjustment Table'; ...
    sprintf('Generated %s; frame ''%s''; roll/pitch/yaw about %s, %s, %s', ...
        datestr(now, 'yyyy-mm-dd HH:MM'), pinfo.origins(pinfo.origin_active).name, axes(1), axes(2), axes(3)); ...
    ['Leg entry = unit ratio x Turn [deg]: the actuator turn of each leg for a small move in the + direction of the ' ...
     'row''s axis of that origin''s frame (sign gives the direction of turn: positive extends the leg, negative retracts it).']};
end


function txt = table_text(rows, dec, head)
%TABLE_TEXT  Plain-text table with box lines, origin names once per group.
fmt = sprintf('%%.%df', dec);
cols = [{'Origin', 'Axis'}, arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false), {'Turn [deg]'}];
body = cell(numel(rows), 9);
for k = 1:numel(rows)
    body{k,1} = rows(k).name;  body{k,2} = rows(k).axis;
    for j = 1:6, body{k,2+j} = sprintf(fmt, rows(k).values(j)); end
    body{k,9} = sprintf('%.1f', rows(k).turn);
end
widths = cellfun(@length, cols);
for k = 1:numel(rows)
    widths = max(widths, cellfun(@length, body(k,:)));
end
sep = ['+' strjoin(arrayfun(@(w) repmat('-', 1, w+2), widths, 'Uni', false), '+') '+'];
lines = [head; {''; sep; fmt_line(cols, widths, 'lllllllll'); sep}];
prev = 0;
for k = 1:numel(rows)
    if prev ~= 0 && rows(k).origin ~= prev, lines{end+1} = sep; end
    cells = body(k,:);
    if rows(k).origin == prev, cells{1} = ''; end
    lines{end+1} = fmt_line(cells, widths, 'llrrrrrrr');
    prev = rows(k).origin;
end
lines{end+1} = sep;
txt = [strjoin(lines, newline) newline];
end


function s = fmt_line(cells, widths, align)
parts = cell(1, numel(cells));
for i = 1:numel(cells)
    if align(i) == 'l'
        parts{i} = [' ' cells{i} repmat(' ', 1, widths(i) - length(cells{i})) ' '];
    else
        parts{i} = [' ' repmat(' ', 1, widths(i) - length(cells{i})) cells{i} ' '];
    end
end
s = ['|' strjoin(parts, '|') '|'];
end


function export_xlsx(path, rows, dec, head, previews)
%EXPORT_XLSX  The table as in the program (Origin, Axis, Leg 1..6, Turn [deg])
%   with the leg cells as live formulas = unit ratio x turn; the unit ratios
%   are on a second sheet, hidden where the MATLAB release allows.  A row is
%   reset by entering 1.0 in its Turn cell.
cols = [{'Origin', 'Axis'}, arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false), {'Turn [deg]'}];
n = numel(rows);
rHdr = 11;                                % header row of the main table (below the 9-row header block)
out = cell(rHdr + n + 2, 9);
unit = cell(rHdr + n, 8);
blocks = [1 2 4];                         % rows of the title, provenance and definition
for i = 1:numel(head), out{blocks(i), 1} = head{i}; end
out(rHdr, :) = cols;
unit(rHdr, :) = [{'Origin', 'Axis'}, arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false)];
letters = 'CDEFGH';
prev = 0;
for k = 1:n
    r = rHdr + k;
    if rows(k).origin ~= prev, out{r, 1} = rows(k).name; prev = rows(k).origin; end
    out{r, 2} = rows(k).axis;
    unit{r, 1} = rows(k).name;  unit{r, 2} = rows(k).axis;
    for j = 1:6
        unit{r, 2 + j} = rows(k).unit(j);
        out{r, 2 + j} = sprintf('=''Unit ratios''!%s%d*$I$%d', letters(j), r, r);
    end
    out{r, 9} = rows(k).turn;
end
out{rHdr + n + 2, 1} = 'Turn [deg] is the input; enter 1.0 to reset a row.';
if isfile(path), delete(path); end
if exist('writecell', 'file')
    writecell(out, path, 'Sheet', 'Incremental Adj');
    writecell(unit, path, 'Sheet', 'Unit ratios');
else
    xlswrite(path, out, 'Incremental Adj');
    xlswrite(path, unit, 'Unit ratios');
end
% Windows with Excel installed: hide the ratio sheet, merge and wrap the
% header text over A..E, colour the Leg headers and put the legend in the
% Turn column, and place the origin previews (with their names) on the right
% (the writecell output alone cannot carry pictures, merges or colours).
try
    ex = actxserver('Excel.Application');
    wb = ex.Workbooks.Open(path);
    wb.Sheets.Item('Unit ratios').Visible = 0;
    sh = wb.Sheets.Item('Incremental Adj');
    colors = [0 114 189; 217 83 25; 237 177 32; 126 47 142; 119 172 48; 77 190 238];
    % the header text in a fixed block of nine rows: title A1:E1, provenance
    % A2:E3, definition A4:E9 (merged, wrapped); the table starts at row 11
    blocks = [1 1; 2 3; 4 9];
    for i = 1:numel(head)
        rg = sh.Range(sprintf('A%d:E%d', blocks(i, 1), blocks(i, 2)));  rg.Merge();  rg.WrapText = true;  rg.VerticalAlignment = -4160;
    end
    sh.Rows.Item(1).RowHeight = 20;
    rHdr = 11;
    for j = 1:6
        c = sh.Cells.Item(rHdr, 2 + j);  c.Font.Bold = true;  c.Font.Color = colors(j,1) + 256*colors(j,2) + 65536*colors(j,3);
        c = sh.Cells.Item(1 + j, 9);  c.Value = sprintf('Leg %d', j);  c.Font.Bold = true;
        c.Font.Color = colors(j,1) + 256*colors(j,2) + 65536*colors(j,3);
    end
    left = sh.Cells.Item(2, 6).Left;  top = sh.Cells.Item(2, 6).Top;
    for k = 1:numel(previews)
        sketchFile = [tempname '.png'];
        f = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [1 1 1.25 1.3], ...
                   'PaperUnits', 'inches', 'PaperPosition', [0 0 1.25 1.3]);
        export_sketch_axes(axes(f, 'Units', 'normalized', 'Position', [0 0 1 1]), previews(k).base, previews(k).plat, previews(k).frame);
        print(f, sketchFile, '-dpng', '-r200');  close(f);
        % -1 width keeps the picture's own aspect ratio at the given height
        sh.Shapes.AddPicture(sketchFile, false, true, left + (k - 1) * 1.35 * 72, top, -1, 1.3 * 72);
        delete(sketchFile);
        lab = sh.Cells.Item(1, 4 + 2 * k);  lab.Value = previews(k).name;  lab.Font.Bold = true;
        rg = sh.Range(sprintf('%s1:%s1', char('A' + 3 + 2 * k), char('A' + 4 + 2 * k)));  rg.Merge();  rg.HorizontalAlignment = -4108;
    end
    wb.Save();  wb.Close();  ex.Quit();  delete(ex);
catch
end
end


function export_png(path, rows, dec, head, previews)
%EXPORT_PNG  Rendered table (white background, black grid, bold reference
%   legs, merged origin cells), sized to the content.
fmt = sprintf('%%.%df', dec);
cols = [{'Origin', 'Axis'}, arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false), {'Turn [deg]'}];
n = numel(rows);
colW = [1.45 0.75 0.85 0.85 0.85 0.85 0.85 0.85 0.9];  % inches
rowH = 0.28;
% header lines are wrapped at the left half of the table (the sketch and the
% legend take the right half)
maxChars = floor((0.5 * sum(colW) - 0.15) / 0.062);
wrapped = {};
for i = 1:numel(head)
    words = strsplit(head{i}, ' ');
    cur = '';
    for w = 1:numel(words)
        if isempty(cur), trial = words{w}; else, trial = [cur ' ' words{w}]; end
        if ~isempty(cur) && length(trial) > maxChars
            wrapped{end+1} = cur; cur = words{w};
        else
            cur = trial;
        end
    end
    wrapped{end+1} = cur;
    if i == 1, titleLines = numel(wrapped); end
end
sketchH = 1.3;  labelH = 0.2;  legendW = 0.7;
if isempty(previews), pictH = 0; else, pictH = 0.12 + labelH + sketchH; end
headH = max(0.15 + 0.22 * numel(wrapped), pictH) + 0.1;
figW = sum(colW) + 0.4;
figH = headH + rowH * (n + 1) + 0.3;
f = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', 'Position', [1 1 figW figH], ...
           'PaperUnits', 'inches', 'PaperPosition', [0 0 figW figH]);
ax = axes(f, 'Units', 'normalized', 'Position', [0 0 1 1], 'Visible', 'off');
xlim(ax, [0 figW]); ylim(ax, [0 figH]); hold(ax, 'on');
yTop = figH - 0.15;
for i = 1:numel(wrapped)
    if i <= titleLines, fs = 10; fw = 'bold'; else, fs = 7.5; fw = 'normal'; end
    text(ax, 0.2, yTop, wrapped{i}, 'FontSize', fs, 'FontWeight', fw, 'VerticalAlignment', 'top');
    yTop = yTop - 0.22;
end
xE = [0.2, 0.2 + cumsum(colW)];
yE = (figH - headH) - (0:n+1) * rowH;
legColors = {'#0072BD', '#D95319', '#EDB120', '#7E2F8E', '#77AC30', '#4DBEEE'};
for c = 1:9
    if c >= 3 && c <= 8, col = legColors{c - 2}; else, col = 'k'; end
    text(ax, 0.5*(xE(c)+xE(c+1)), 0.5*(yE(1)+yE(2)), cols{c}, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'FontSize', 8.5, 'FontWeight', 'bold', 'Color', col);
end
% origin previews centred in the right half (between the middle and the
% legend), each with its name above; legend at the right edge
areaX0 = 0.2 + 0.5 * sum(colW);  areaX1 = 0.2 + sum(colW) - legendW;
nP = numel(previews);  gap = 0.15;
if nP > 0
    skW = min(sketchH * 1.7, (areaX1 - areaX0 - gap * (nP + 1)) / nP);
    total = nP * skW + gap * (nP - 1);
    x = 0.5 * (areaX0 + areaX1) - 0.5 * total;
    skY = figH - 0.12 - labelH - sketchH;
    for k = 1:nP
        text(ax, x + 0.5 * skW, skY + sketchH + 0.04, previews(k).name, 'FontSize', 8, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
        axS = axes(f, 'Units', 'inches', 'Position', [x skY skW sketchH]);
        export_sketch_axes(axS, previews(k).base, previews(k).plat, previews(k).frame);
        x = x + skW + gap;
    end
end
for j = 1:6
    text(ax, 0.2 + sum(colW), figH - 0.15 - (j - 1) * 0.24, sprintf('Leg %d', j), 'FontSize', 8.5, ...
        'FontWeight', 'bold', 'Color', legColors{j}, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top');
end
groupFirst = [];  groupLast = [];  prev = 0;
for k = 1:n
    r = rows(k);
    if r.origin ~= prev, groupFirst(end+1) = k; groupLast(end+1) = k; prev = r.origin; else, groupLast(end) = k; end %#ok<AGROW>
    yc = 0.5*(yE(k+1)+yE(k+2));
    text(ax, 0.5*(xE(2)+xE(3)), yc, r.axis, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontSize', 8.5);
    for j = 1:6
        if any(r.bold == j)
            % double bold: drawn twice, one pixel apart
            text(ax, xE(j+3) - 0.08, yc, sprintf(fmt, r.values(j)), 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'middle', 'FontSize', 8.5, 'FontWeight', 'bold');
            text(ax, xE(j+3) - 0.08 + 0.005, yc, sprintf(fmt, r.values(j)), 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'middle', 'FontSize', 8.5, 'FontWeight', 'bold');
        else
            text(ax, xE(j+3) - 0.08, yc, sprintf(fmt, r.values(j)), 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'middle', 'FontSize', 8.5);
        end
    end
    text(ax, xE(10) - 0.08, yc, sprintf('%.1f', r.turn), 'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle', 'FontSize', 8.5);
end
for g = 1:numel(groupFirst)
    yc = 0.5*(yE(groupFirst(g)+1) + yE(groupLast(g)+2));
    if groupLast(g) > groupFirst(g), nm = wrap_origin_name(rows(groupFirst(g)).name); else, nm = {rows(groupFirst(g)).name}; end
    text(ax, 0.5*(xE(1)+xE(2)), yc, nm, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontSize', 8.5);
end
plot(ax, [xE(1) xE(end)], [yE(1) yE(1)], 'k', 'LineWidth', 0.8);
plot(ax, [xE(1) xE(end)], [yE(2) yE(2)], 'k', 'LineWidth', 0.8);
plot(ax, [xE(1) xE(end)], [yE(end) yE(end)], 'k', 'LineWidth', 0.8);
for c = 1:numel(xE), plot(ax, [xE(c) xE(c)], [yE(1) yE(end)], 'k', 'LineWidth', 0.8); end
for k = 2:n
    edge = rows(k).origin ~= rows(k-1).origin;
    if edge, x0 = xE(1); lw = 0.8; else, x0 = xE(2); lw = 0.4; end
    plot(ax, [x0 xE(end)], [yE(k+1) yE(k+1)], 'k', 'LineWidth', lw);
end
print(f, path, '-dpng', '-r200');
close(f);
end
