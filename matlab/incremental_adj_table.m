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
%   any unit ratio whose rounded magnitude exceeds the chosen threshold, but
%   is below 1, to exactly 1; its last entry turns that off.  Bold
%   marks the legs whose unit ratio reads +/-1, decided at turn = 1.0 and kept
%   as the turns change.  "Reset turns" puts every turn back to 1.0.  Export
%   writes the table as text, Excel (live formulas) or PNG, always of the unit
%   table (every turn 1.0), leaving the window's own turns alone.  Confirm
%   keeps the set-up (ticks, labels, turns, decimals) in the program (saved by
%   Save Everything); Close discards the changes.

pinfo = get(mainFig, 'UserData');
origins = pinfo.origins;
nO = numel(origins);
cfg = adj_config_normalise(pinfo.adj_config, nO);
anyTicks = any(cfg.masks(:));
% The view settings (decimals, round-up threshold, pose choice) live for as
% long as the program runs, so reopening the window finds them as they were
% left, whether it was closed with Confirm or with Close.  They are not part of
% the saved set-up.
if isfield(pinfo, 'adj_view') && isstruct(pinfo.adj_view)
    vw = pinfo.adj_view;
else
    vw = struct('decimals', cfg.decimals, 'roundUp', 0.99, 'fromHome', true);
end
if ~isfield(vw, 'decimals'), vw.decimals = cfg.decimals; end
if ~isfield(vw, 'roundUp'),  vw.roundUp  = 0.99; end
if ~isfield(vw, 'fromHome'), vw.fromHome = true; end
AXES = {'X', 'Y', 'Z', 'Roll', 'Pitch', 'Yaw'};
M = 15;  ROW_H = 24;  GAP = 8;  BTN_H = 28;
% wide enough for the widest table the Label column can produce (18 characters)
W = max(760, 118 + 56 + (18 * 7 + 24) + 6 * 70 + 72 + 4 + 2 * M);
hHdr = 18;  hDec = 24;  hUser = 15;   % hUser: the "user input" marks above the table
hIntro = 0;                           % set below, from the wrapped line count
tableRows = 8;                         % visible rows before the uitable scrolls
hTable = hHdr + tableRows * ROW_H + 8;
H = M + (3 * 17 + 6) + GAP + hHdr + nO * ROW_H + GAP + hDec + hUser + GAP + hTable + GAP + BTN_H + M;

d = dialog('Name', 'Incremental Adjustment Table', 'WindowStyle', 'modal', ...
           'Resize', 'off', 'Visible', 'off', 'Position', [0 0 W H]);
movegui(d, 'center');
bg = get(d, 'Color');
setappdata(d, 'mainFig', mainFig);

introText = ['Tick the axes to tabulate. Leg entry = unit ratio x Turn [deg]: the actuator turn of each leg ' ...
             'for a small move in the + direction of the row''s axis of that origin''s frame (sign gives the ' ...
             'direction of turn: positive extends the leg, negative retracts it).'];
introLines = wrap_text(introText, floor((W - 2*M) / 6.2));   % fills the window, whatever its width
hIntro = numel(introLines) * 17 + 6;
y = H - M - hIntro;                                         % the block starts below the top margin
uicontrol(d, 'Style', 'text', 'Position', [M y W-2*M hIntro], 'FontSize', 9, ...
    'HorizontalAlignment', 'left', 'BackgroundColor', bg, 'String', introLines);

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

% --- the row above the table: four label + control pairs, spread evenly ---
% Each pair is measured from its own text, the first is flush with the table's
% left edge and the last with its right edge, and the space left over is shared
% equally between them, so the row stays evenly spaced whatever the table's
% width or the wording.
y = y - GAP - hDec;
labelW = numel('Label') * 7 + 24;            % the Label column (grows with its entries)
tableW = 118 + 56 + labelW + 6 * 70 + 72 + 4;
tableX = round((W - tableW) / 2);
yBox = y + round((hDec - 16) / 2);           % the 16 px band the buttons sit on

tipDec   = 'Decimal places of the leg entries';
tipHome  = 'Compute the table at the zero-displacement (home) configuration';
tipNew   = 'Compute the table at the new absolute pose shown in the main window';
tipRound = ['Show a unit ratio whose rounded magnitude is above this, but below 1, ' ...
            'as exactly 1 (and mark that leg bold)'];
roundVals = [0.9 0.95 0.99 0.999 0];         % the "Round up above:" menu; 0 = off
roundTexts = {'0.9', '0.95', '0.99', '0.999', '- off -'};

texts = {'Decimal places:', 'From Home', 'From New', 'Round up above:'};
tips  = {tipDec, tipHome, tipNew, tipRound};
ctrlW = [64 18 18 72];                       % a menu, two buttons, a menu
GAP_LC = 6;                                  % between a label and its control
labW  = cellfun(@(t) numel(t) * 7 + 4, texts);
pairW = labW + GAP_LC + ctrlW;
step  = max(tableW - sum(pairW), 0) / (numel(texts) - 1);

x = tableX;  xs = zeros(1, numel(texts));
for i = 1:numel(texts)
    xs(i) = x;
    uicontrol(d, 'Style', 'text', 'Position', [x yBox labW(i) 16], 'String', texts{i}, ...
        'HorizontalAlignment', 'right', 'BackgroundColor', bg, 'TooltipString', tips{i});
    x = x + pairW(i) + step;
end

hDecPop = uicontrol(d, 'Style', 'popupmenu', ...
    'Position', [xs(1) + labW(1) + GAP_LC, y, ctrlW(1), hDec], ...
    'String', {'0','1','2','3','4','5','6'}, 'Value', vw.decimals + 1, ...
    'TooltipString', tipDec, 'Callback', @(~, ~) refresh(d));
setappdata(d, 'decPop', hDecPop);

hFromHome = uicontrol(d, 'Style', 'radiobutton', ...
    'Position', [xs(2) + labW(2) + GAP_LC, yBox + 1, ctrlW(2), 16], ...
    'String', '', 'Value', double(vw.fromHome), 'BackgroundColor', bg, 'TooltipString', tipHome, ...
    'Callback', @(~, ~) pose_picked(d, 1));
hFromNew = uicontrol(d, 'Style', 'radiobutton', ...
    'Position', [xs(3) + labW(3) + GAP_LC, yBox + 1, ctrlW(3), 16], ...
    'String', '', 'Value', double(~vw.fromHome), 'BackgroundColor', bg, 'TooltipString', tipNew, ...
    'Callback', @(~, ~) pose_picked(d, 2));
setappdata(d, 'poseBtns', [hFromHome hFromNew]);

hRound = uicontrol(d, 'Style', 'popupmenu', ...
    'Position', [xs(4) + labW(4) + GAP_LC, y, ctrlW(4), hDec], ...
    'String', roundTexts, ...
    'Value', max(find(abs(roundVals - vw.roundUp) < 1e-9, 1), 1), 'TooltipString', tipRound, ...
    'Callback', @(~, ~) refresh(d));
setappdata(d, 'roundPop', hRound);
setappdata(d, 'roundVals', roundVals);
% whichever way the window is closed, the view settings go back to the program
set(d, 'DeleteFcn', @(~, ~) save_view(d, mainFig));

% --- table ---
y = y - hUser;
hUser1 = uicontrol(d, 'Style', 'text', 'Position', [tableX y 90 hUser], 'String', 'user input', ...
    'FontSize', 8, 'FontAngle', 'italic', 'ForegroundColor', [0.53 0.53 0.53], ...
    'HorizontalAlignment', 'center', 'BackgroundColor', bg);
hUser2 = uicontrol(d, 'Style', 'text', 'Position', [tableX y 90 hUser], 'String', 'user input', ...
    'FontSize', 8, 'FontAngle', 'italic', 'ForegroundColor', [0.53 0.53 0.53], ...
    'HorizontalAlignment', 'center', 'BackgroundColor', bg);
setappdata(d, 'userMarks', [hUser1 hUser2]);

y = y - 2 - hTable;                          % the marks sit just above the table
hT = uitable(d, 'Position', [tableX y tableW hTable], ...   % centred (tableX / tableW above)
    'ColumnName', [{'Origin', 'Axis', 'Label'}, ...
                   arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false), {'Turn [deg]'}], ...
    'ColumnWidth', {118, 56, labelW, 70, 70, 70, 70, 70, 70, 72}, 'RowName', [], ...
    'ColumnEditable', [false false false false false false false false false true], ...
    'TooltipString', 'Click a Label cell to name that row', ...
    'ColumnFormat', repmat({'char'}, 1, 10), 'CellEditCallback', @(src, evt) cell_edited(d, evt), ...
    'CellSelectionCallback', @(src, evt) label_clicked(d, evt));
setappdata(d, 'table', hT);
labelMap = containers.Map('KeyType', 'char', 'ValueType', 'char');
AXES_L = {'X', 'Y', 'Z', 'Roll', 'Pitch', 'Yaw'};
for i = 1:nO
    for c = 1:6
        if ~isempty(cfg.labels{i, c})
            labelMap(sprintf('%d|+%s', i, AXES_L{c})) = cfg.labels{i, c};
        end
    end
end
setappdata(d, 'labels', labelMap);
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


function place_user_marks(d, colWidths)
%PLACE_USER_MARKS  Centre the two "user input" marks over the Label and the
%   Turn columns, wherever the current column widths put them.
h = getappdata(d, 'userMarks');
hT = getappdata(d, 'table');
if isempty(h) || isempty(hT), return; end
pos = get(hT, 'Position');
x0 = pos(1) + 1;
w = cell2mat(colWidths);
centres = [x0 + sum(w(1:2)) + w(3) / 2, x0 + sum(w(1:9)) + w(10) / 2];
for i = 1:2
    p = get(h(i), 'Position');
    set(h(i), 'Position', [round(centres(i) - p(3) / 2) p(2) p(3) p(4)]);
end
end


function lines = wrap_text(txt, maxChars)
%WRAP_TEXT  Break a sentence into lines of at most maxChars characters,
%   at spaces only.  A text control clips rather than wraps, so the caller
%   sizes its box from the number of lines returned.
words = strsplit(char(txt));
lines = {};
cur = '';
for k = 1:numel(words)
    if isempty(cur), trial = words{k}; else, trial = [cur ' ' words{k}]; end
    if ~isempty(cur) && numel(trial) > maxChars
        lines{end+1} = cur; %#ok<AGROW>
        cur = words{k};
    else
        cur = trial;
    end
end
lines{end+1} = cur;
lines = lines(:);
end


function pose_picked(d, which)
%POSE_PICKED  One or the other, never both, and never neither.
h = getappdata(d, 'poseBtns');
set(h(which), 'Value', 1);
set(h(3 - which), 'Value', 0);
refresh(d);
end


function save_view(d, mainFig)
%SAVE_VIEW  Hand the decimals, the round-up threshold and the pose choice back
%   to the main window, so reopening the table finds them unchanged.
if ~isgraphics(mainFig), return; end
try
    pinfo = get(mainFig, 'UserData');
    pinfo.adj_view = struct('decimals', decimals(d), 'roundUp', round_up(d), ...
                            'fromHome', from_home(d));
    set(mainFig, 'UserData', pinfo);
catch
end
end


function tf = from_home(d)
h = getappdata(d, 'poseBtns');
tf = isempty(h) || logical(get(h(1), 'Value'));
end


function thr = round_up(d)
%ROUND_UP  The selected round-up threshold (0.9, 0.95, 0.99 or 0.999).
h = getappdata(d, 'roundPop');
vals = getappdata(d, 'roundVals');
if isempty(h) || isempty(vals)
    thr = 0.99;
else
    thr = vals(get(h, 'Value'));
end
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
labels = getappdata(d, 'labels');
for i = 1:nO
    for c = 1:6
        key = sprintf('%d|+%s', i, AXES6{c});
        if isKey(turns, key), cfg.turns(i, c) = turns(key); end
        if ~isempty(labels) && isKey(labels, key), cfg.labels{i, c} = labels(key); end
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
labels = getappdata(d, 'labels');
dec = decimals(d);
snapUp = round_up(d);
for k = 1:numel(rows)
    key = row_key(rows(k));
    if ~isempty(labels) && isKey(labels, key)
        rows(k).label = labels(key);   % the user's text ...
    else
        rows(k).label = rows(k).axis;  % ... or the row's axis until it is edited
    end
    if isKey(turns, key), m = turns(key); else, m = 1.0; end
    rows(k).turn = max(-99999.9, min(99999.9, round(m, 1)));
    unit = round(rows(k).ratios, dec);
    if snapUp > 0 && snapUp < 1
        snap = abs(unit) > snapUp & abs(unit) < 1;
        unit(snap) = sign(unit(snap));
    end
    rows(k).unit = unit;
    rows(k).values = unit * rows(k).turn;
    rows(k).bold = find(abs(abs(round(unit, dec)) - 1) < 1e-12);
end
end


function label_clicked(d, evt)
%LABEL_CLICKED  Clicking a Label cell asks for that row's name.
%
%   The column is displayed rather than edited in place: MATLAB loads its cell
%   editor with the raw cell string, so a formatted (bold, coloured) cell would
%   show its markup there and could not be edited reliably.  A small prompt
%   keeps the formatting and the editing both dependable.
if isempty(evt.Indices) || evt.Indices(2) ~= 3, return; end
rows = getappdata(d, 'rows');
k = evt.Indices(1);
if k > numel(rows), return; end
% One fixed width, the worst case the prompt can reach: the longest axis
% ('+Pitch') and the longest origin name (22 characters).  The wording never
% wraps and the box is never wider than it needs to be.
prompt = sprintf('Label for %s of ''%s'' (up to 18 characters):', rows(k).axis, rows(k).name);
width = numel(sprintf('Label for +Pitch of ''%s'' (up to 18 characters):', repmat('X', 1, 22)));
answer = inputdlg(prompt, 'Row label', [1 width], {rows(k).label});
if isempty(answer), return; end
txt = strrep(strtrim(answer{1}), '"', '');
if numel(txt) > 18, txt = txt(1:18); end
labels = getappdata(d, 'labels');
labels(row_key(rows(k))) = txt;
setappdata(d, 'labels', labels);
refresh(d);
end


function cell_edited(d, evt)
%CELL_EDITED  A Turn cell was edited: it must be a number (positive or
%   negative), rounded to one decimal, and the row is recomputed.  Labels are
%   handled by label_clicked.
rows = getappdata(d, 'rows');
k = evt.Indices(1);
if k > numel(rows), return; end
if evt.Indices(2) ~= 10, return; end
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
rows = with_turns(d, incremental_adj_rows(mainFig, selections(d), from_home(d)));
setappdata(d, 'rows', rows);
dec = decimals(d);
fmt = sprintf('%%.%df', dec);
hT = getappdata(d, 'table');

% The Label column fits its longest entry (its own header at a minimum), and
% the table is then resized and re-centred so no column is ever cut off.
labChars = max([numel('Label'), cellfun(@numel, {rows.label})]);
w = get(hT, 'ColumnWidth');
w{3} = labChars * 7 + 24;
widths = cell2mat(w);
pos = get(hT, 'Position');
total = sum(widths) + 4;
figPos = get(d, 'Position');
set(hT, 'ColumnWidth', w, 'Position', [round((figPos(3) - total) / 2) pos(2) total pos(4)]);

% MATLAB's table cannot merge cells, so an origin's name is written on the
% middle row of its group (centred over the group by eye); a two-word name of
% a group with at least two rows is split over the two middle rows.
data = cell(numel(rows), 10);
nameRows = containers.Map('KeyType', 'double', 'ValueType', 'any');
groups = unique([rows.origin], 'stable');
for g = groups
    idx = find([rows.origin] == g);
    lines = {rows(idx(1)).name};
    if numel(idx) > 1
        wrapped = wrap_origin_name(rows(idx(1)).name, 11);
        if numel(wrapped) > 1, lines = wrapped; end
    end
    mid = idx(1) + floor((numel(idx) - numel(lines)) / 2);
    for t = 1:numel(lines)
        nameRows(mid + t - 1) = lines{t};
    end
end
for k = 1:numel(rows)
    r = rows(k);
    % Read-only cells are laid out with HTML.  The width has to be stated:
    % without it the block is only as wide as its text and the alignment has
    % nothing to work with, which is why these columns stayed left-aligned.
    if isKey(nameRows, k)
        data{k, 1} = html_cell(nameRows(k), widths(1), 'center', '');
    else
        data{k, 1} = '';
    end
    data{k, 2} = html_cell(r.axis, widths(2), 'center', '');
    % The Label and Turn cells are editable, so they must hold plain text:
    % MATLAB puts the raw cell string into the editor, and HTML markup would
    % appear there as markup.  They are aligned with spaces instead.
    % the label: bold and dark red, like the exports (it is not edited in
    % place, so it can carry formatting; label_clicked opens a small prompt)
    data{k, 3} = html_cell(r.label, widths(3), 'center', 'bold', '#C00000');
    for j = 1:6
        if any(r.bold == j), wt = 'heavy'; else, wt = ''; end
        data{k, 3 + j} = html_cell(sprintf(fmt, r.values(j)), widths(3 + j), 'right', wt);
    end
    data{k, 10} = pad_text(sprintf('%.1f', r.turn), widths(10), 'right');
end
set(hT, 'Data', data);
place_user_marks(d, w);
end


function out = html_cell(txt, widthPx, align, weight, colour)
%HTML_CELL  A read-only table cell, aligned inside an explicit width (MATLAB
%   ignores the alignment without one), optionally bold or heavy bold and in a
%   colour.  weight: '' | 'bold' | 'heavy'.
inner = char(txt);
if nargin >= 5 && ~isempty(colour)
    inner = ['<font color="' colour '">' inner '</font>'];
end
switch char(weight)
    case 'heavy', inner = ['<b style="font-weight:900">' inner '</b>'];
    case 'bold',  inner = ['<b>' inner '</b>'];
end
out = sprintf('<html><div align="%s" style="width:%dpx">%s</div></html>', ...
              align, max(widthPx - 24, 10), inner);
end


function out = pad_text(txt, widthPx, align)
%PAD_TEXT  Line up an EDITABLE cell with spaces.
%
%   MATLAB gives no alignment control for table columns, and the HTML that
%   aligns the read-only columns cannot be used here: the editor is loaded
%   with the cell's raw string, so an HTML cell shows its markup and, worse,
%   cannot be edited reliably.  Spaces are the only option that keeps the
%   column editable.  A character of this font is about 6.2 px wide and a
%   space about 3.2, and the cell takes about 6 px of inset; the indent is
%   capped so a long entry is never pushed out of view.
txt = char(txt);
CHAR_PX = 6.2;  SPACE_PX = 3.2;  INSET_PX = 6;
free = max(widthPx - INSET_PX - CHAR_PX * numel(txt), 0);
switch align
    case 'center', pad = round(free / 2 / SPACE_PX);
    case 'right',  pad = round(free / SPACE_PX);
    otherwise,     pad = 0;
end
pad = min(max(pad, 0), floor(free / SPACE_PX));
out = [repmat(' ', 1, pad) txt];
end


function export_table(d, ext)
%EXPORT_TABLE  Export as ext (.png, .txt or .xlsx): one save dialog limited
%   to that type, starting in the last folder used anywhere in the program.
rows = getappdata(d, 'rows');
if isempty(rows)
    uiwait(msgbox('Tick at least one axis first.', 'Nothing to export', 'modal'));
    return;
end
% An export is always of the unit table: every turn 1.0, so the file shows the
% ratios themselves.  The turns typed in the window are left exactly as they are.
for k = 1:numel(rows)
    rows(k).turn = 1;
    rows(k).values = rows(k).unit;
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
head = header_lines(pinfo, dec, from_home(d));
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


function s = pose_source(pinfo, fromHome)
%POSE_SOURCE  How the export header describes the pose the table came from.
if fromHome
    s = 'from the home pose';
else
    getVal = @(f) str2double(get(pinfo.(f), 'String'));
    s = sprintf(['from new absolute pose (X, Y, Z) = (%.3f, %.3f, %.3f) mm, ' ...
                 '(roll, pitch, yaw) = (%.3f, %.3f, %.3f) deg in the ''%s'' frame'], ...
                getVal('Pxval'), getVal('Pyval'), getVal('Pzval'), ...
                getVal('roll'), getVal('pitch'), getVal('yaw'), ...
                pinfo.origins(pinfo.origin_active).name);
end
end


function head = header_lines(pinfo, dec, fromHome)
axes = rpy_axes_of(pinfo);
head = { 'Incremental Adjustment Table'; ...
    sprintf('Generated %s %s; roll/pitch/yaw about %s, %s, %s', ...
        datestr(now, 'dd mmmm yyyy'), pose_source(pinfo, fromHome), axes(1), axes(2), axes(3)); ...
    ['Leg entry = unit ratio x Turn [deg]: the actuator turn of each leg for a small move in the + direction of the ' ...
     'row''s axis of that origin''s frame (sign gives the direction of turn: positive extends the leg, negative retracts it).']};
end


function txt = table_text(rows, dec, head)
%TABLE_TEXT  Plain-text table with box lines, origin names once per group.
fmt = sprintf('%%.%df', dec);
cols = [{'Origin', 'Axis', 'Label'}, arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false)];
body = cell(numel(rows), 9);                 % the Turn column is not exported
for k = 1:numel(rows)
    body{k,1} = rows(k).name;  body{k,2} = rows(k).axis;  body{k,3} = rows(k).label;
    for j = 1:6, body{k,3+j} = sprintf(fmt, rows(k).values(j)); end
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
    lines{end+1} = fmt_line(cells, widths, 'lllrrrrrr');
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
%EXPORT_XLSX  Write the table as an Excel workbook, laid out exactly like the
%   PNG export and the Python version.
%
%   Two stages:
%     1. writecell puts the text and the NUMBERS on two sheets.  Formulas are
%        deliberately not written here: writecell stores a leading "=" as
%        text, which Excel then shows literally until the cell is re-entered.
%     2. If Excel is reachable through COM (Windows with Excel installed) the
%        workbook is reopened and finished: live formulas (leg = unit ratio x
%        Turn), merged and wrapped header block, merged origin cells, borders,
%        number formats, the coloured Leg headers and legend, the origin
%        previews, and the hidden unit-ratio sheet.  Alerts are switched off
%        first, because Excel's "merging cells only keeps the upper-left
%        value" prompt would otherwise block MATLAB with an invisible dialog,
%        and the Excel process is quit even if something goes wrong, so no
%        locked workbook is left behind.
%     Without COM (macOS, Linux, no Excel) stage 1 alone gives a complete,
%     correct workbook: the same numbers, without pictures, colours or live
%     formulas.

cols = [{'Origin', 'Axis', 'Label'}, arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false), {'Turn [deg]'}];
n = numel(rows);
legCol = 4;                               % D: the first Leg column
turnCol = 10;                             % J: the Turn column, beside the table
rHdr = 11;                                % header row (below the 9-row header block)
out  = cell(rHdr + n + 2, 10);
unit = cell(rHdr + n, 8);
blocks = [1 2 5];                         % rows of the title, provenance and definition
for i = 1:numel(head), out{blocks(i), 1} = head{i}; end
out(rHdr, :) = cols;
out{rHdr - 1, turnCol} = 'user input';   % centred by format_workbook
unit(rHdr, :) = [{'Origin', 'Axis'}, arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false)];
prev = 0;
groupFirst = [];  groupLast = [];
for k = 1:n
    r = rHdr + k;
    if rows(k).origin ~= prev
        out{r, 1} = rows(k).name;  unit{r, 1} = rows(k).name;
        prev = rows(k).origin;
        groupFirst(end+1) = k;  groupLast(end+1) = k; %#ok<AGROW>
    else
        groupLast(end) = k;
    end
    out{r, 2} = rows(k).axis;  unit{r, 2} = rows(k).axis;
    out{r, 3} = rows(k).label;
    for j = 1:6
        unit{r, 2 + j} = rows(k).unit(j);
        out{r, legCol - 1 + j} = rows(k).values(j);   % replaced by a formula below
    end
    out{r, turnCol} = rows(k).turn;
end
out{rHdr + n + 2, 1} = 'Turn [deg] is the input; enter 1.0 to reset a row.';

if isempty(fileparts(path)), path = fullfile(pwd, path); end
if isfile(path)
    [ok, msg] = delete_file(path);
    if ~ok
        error('The workbook could not be replaced (%s). Close it in Excel and export again.', msg);
    end
end

% The workbook is built and formatted at a temporary path and only copied to
% the destination once Excel has quit.  Excel therefore never holds the file
% the user is about to open, which is what produced the "locked for editing"
% prompt on the first export.
tmp = [tempname '.xlsx'];
if exist('writecell', 'file')
    writecell(out,  tmp, 'Sheet', 'Incremental Adj');
    writecell(unit, tmp, 'Sheet', 'Unit ratios');
else
    xlswrite(tmp, out,  'Incremental Adj');
    xlswrite(tmp, unit, 'Unit ratios');
end

[pics, picSizes] = render_previews(previews);   % temp PNGs (cropped), deleted below
ex = [];
try
    ex = actxserver('Excel.Application');
catch
    fprintf(['Excel is not available on this machine, so the workbook holds the values only ' ...
             '(no live formulas, pictures or colours).\n']);
end
if ~isempty(ex)
    cleaner = onCleanup(@() quit_excel(ex));
    try
        ex.DisplayAlerts = false;         % no merge / overwrite prompts
        ex.Visible = false;
        ex.ScreenUpdating = false;
        wbs = ex.Workbooks;
        wb = wbs.Open(tmp);
        format_workbook(wb, rows, dec, head, previews, pics, picSizes, rHdr, groupFirst, groupLast);
        wb.Save();
        wb.Close(false);
        release_com(wb, wbs);
    catch err
        fprintf('The workbook was written, but Excel could not finish formatting it: %s\n', err.message);
    end
    clear cleaner                          % quits Excel now, before the copy
    pause(0.2);                            % let the process finish exiting
end
for i = 1:numel(pics)
    if isfile(pics{i}), delete_file(pics{i}); end
end
[ok, msg] = copyfile(tmp, path, 'f');
if ~ok
    error('The workbook could not be written to %s (%s).', path, msg);
end
delete_file(tmp);
end


function release_com(varargin)
%RELEASE_COM  Let go of COM interface objects (Workbook, Range, Sheet, ...).
%   Excel keeps running, and keeps the file locked, while any of them are
%   still referenced, so every handle this code creates is released.
for i = 1:numel(varargin)
    h = varargin{i};
    if isempty(h), continue; end
    try, release(h); catch, end
    try, delete(h); catch, end
end
end


function [pics, sizes] = render_previews(previews)
%RENDER_PREVIEWS  The origin previews as temporary PNGs, cropped to their
%   drawing (a small white margin is kept), and their pixel sizes, so the
%   caller can fit each one into its box at its own aspect ratio.
[pw, ph] = preview_size();
pics = cell(1, numel(previews));
sizes = zeros(numel(previews), 2);          % [height width] in pixels
for k = 1:numel(previews)
    f = figure('Visible', 'off', 'Color', 'w', 'Units', 'inches', ...
               'Position', [1 1 pw ph], 'PaperUnits', 'inches', ...
               'PaperPosition', [0 0 pw ph]);
    ax = axes(f, 'Units', 'normalized', 'Position', [0 0 1 1]); %#ok<LAXES>
    export_sketch_axes(ax, previews(k).base, previews(k).plat, previews(k).frame);
    pics{k} = [tempname '.png'];
    print(f, pics{k}, '-dpng', '-r600');   % four times the pixels of the old export
    close(f);
    sizes(k, :) = crop_png(pics{k}, 10);
end
end


function sz = crop_png(file, pad)
%CROP_PNG  Trim the white margin around a rendered preview, keeping `pad`
%   pixels, and return the cropped size [height width].
im = imread(file);
ink = min(im(:, :, 1:3), [], 3) < 250;
if ~any(ink(:))
    sz = [size(im, 1) size(im, 2)];
    return;
end
rows = find(any(ink, 2));  cols = find(any(ink, 1));
r0 = max(rows(1) - pad, 1);            r1 = min(rows(end) + pad, size(im, 1));
c0 = max(cols(1) - pad, 1);            c1 = min(cols(end) + pad, size(im, 2));
im = im(r0:r1, c0:c1, :);
imwrite(im, file);
sz = [size(im, 1) size(im, 2)];
end


function [w, h] = preview_size()
%PREVIEW_SIZE  Size an origin preview is rendered at [in], before cropping.
w = 1.70;  h = 1.30;
end


function [w, h] = preview_box(count)
%PREVIEW_BOX  The box a preview must fit inside [in]: always two Leg columns
%   wide, six rows tall when two previews are shown and eight when only one
%   is (a spreadsheet row is 15 pt).  Identical rule to adj_table.py.
w = 0.94 * 1.70;                        % a little air on each side
if count <= 1, rows = 8; else, rows = 6; end
h = rows * 15 / 72;
end


function h = preview_band()
%PREVIEW_BAND  Height of the band a preview is centred in [in]: rows 2 to 9,
%   eight rows of 15 pt (identical rule to adj_table.py).
h = 8 * 15 / 72;
end


function [w, h] = fit_in_box(sz, boxW, boxH)
%FIT_IN_BOX  The largest size [in] with the picture's own aspect ratio that
%   fits inside the box, so it is never stretched.  sz = [height width] px.
aspect = sz(2) / sz(1);
if boxW / boxH >= aspect
    h = boxH;  w = boxH * aspect;
else
    w = boxW;  h = boxW / aspect;
end
end


function [ok, msg] = delete_file(f)
ok = true;  msg = '';
try
    delete(f);
    ok = ~isfile(f);
    if ~ok, msg = 'the file is in use'; end
catch err
    ok = false;  msg = err.message;
end
end


function quit_excel(ex)
%QUIT_EXCEL  Close every workbook and quit, whatever state Excel is in, and
%   release the handles, so a failed export cannot leave an invisible Excel
%   process holding the file.
if isempty(ex), return; end
try, ex.DisplayAlerts = false; catch, end
try
    wbs = ex.Workbooks;
    for i = double(wbs.Count):-1:1
        try
            w = wbs.Item(i);
            w.Close(false);
            release_com(w);
        catch
        end
    end
    release_com(wbs);
catch
end
try, ex.Quit(); catch, end
try, release(ex); catch, end
try, delete(ex); catch, end
end


function format_workbook(wb, rows, dec, head, previews, pics, picSizes, rHdr, groupFirst, groupLast)
%FORMAT_WORKBOOK  Everything the plain writecell output cannot carry.
%
%   Every cell is addressed as an A1 range (sh.Range('C12')), never as
%   Cells.Item(row, col): MATLAB passes only the first argument of Item
%   through to Excel, so Item(12, 8) is taken as the linear index 12 and lands
%   on L1 instead of H12.  That is what previously scattered the formulas,
%   the legend and the preview names over row 1.

n = numel(rows);
letters = 'DEFGHI';                            % the six Leg columns
unitLetters = 'CDEFGH';                        % ... on the hidden unit-ratio sheet
turnLetter = 'J';
legColors = [0 114 189; 217 83 25; 237 177 32; 126 47 142; 119 172 48; 77 190 238];
turnColor = 31 + 256*78 + 65536*121;           % the blue of the input column
if dec == 0, numFmt = '0'; else, numFmt = ['0.' repmat('0', 1, dec)]; end
xlContinuous = 1;  xlThin = 2;  xlCenter = -4108;  xlRight = -4152;  xlTop = -4160;  xlBottom = -4107;
labChars = max([numel('Label'), cellfun(@numel, {rows.label})]);
widths = [18 9 max(11, labChars + 2) 11 11 11 11 11 11 10.9];   % A, B, Label, six Legs, Turn

sh = wb.Sheets.Item('Incremental Adj');
sh.Activate();

% ---- column widths, header block, row heights ----
for c = 1:10
    sh.Range(sprintf('%s1', col_letter(c))).EntireColumn.ColumnWidth = widths(c);
end
blocks = [1 1; 2 4; 5 9];                      % title, provenance (three rows), definition (five)
for i = 1:numel(head)
    rg = sh.Range(sprintf('A%d:D%d', blocks(i, 1), blocks(i, 2)));   % A..D, four columns
    rg.Merge();  rg.WrapText = true;  rg.VerticalAlignment = xlTop;
end
sh.Range('A1').Font.Bold = true;  sh.Range('A1').Font.Size = 13;
sh.Range('A1').EntireRow.RowHeight = 20;
for r = 2:9
    sh.Range(sprintf('A%d', r)).EntireRow.RowHeight = 15;
end
sh.Range(sprintf('A%d', rHdr + n + 2)).Font.Italic = true;
note = sh.Range(sprintf('%s%d', turnLetter, rHdr - 1));      % the "user input" mark
note.Font.Italic = true;  note.HorizontalAlignment = xlCenter;

% ---- table header, coloured Leg columns, legend in the Turn column ----
hdr = sh.Range(sprintf('A%d:J%d', rHdr, rHdr));
hdr.Font.Bold = true;  hdr.HorizontalAlignment = xlCenter;  hdr.VerticalAlignment = xlCenter;
for j = 1:6
    c = sh.Range(sprintf('%s%d', letters(j), rHdr));
    c.Font.Color = legColors(j,1) + 256*legColors(j,2) + 65536*legColors(j,3);
    c = sh.Range(sprintf('I%d', 1 + j));       % legend, centred in its column
    c.Value = sprintf('Leg %d', j);  c.Font.Bold = true;
    c.HorizontalAlignment = xlCenter;  c.VerticalAlignment = xlCenter;
    c.Font.Color = legColors(j,1) + 256*legColors(j,2) + 65536*legColors(j,3);
end

% ---- body: live formulas, formats, bold reference legs ----
for k = 1:n
    r = rHdr + k;
    for j = 1:6
        c = sh.Range(sprintf('%s%d', letters(j), r));
        c.Formula = sprintf('=''Unit ratios''!%s%d*$%s$%d', unitLetters(j), r, turnLetter, r);
        c.NumberFormat = numFmt;
        c.HorizontalAlignment = xlRight;  c.VerticalAlignment = xlCenter;
        if any(rows(k).bold == j), c.Font.Bold = true; end
    end
    t = sh.Range(sprintf('%s%d', turnLetter, r));
    t.NumberFormat = '0.0';  t.HorizontalAlignment = xlRight;  t.VerticalAlignment = xlCenter;
    t.Font.Color = turnColor;
    ax = sh.Range(sprintf('B%d:C%d', r, r));   % Axis and Label, both centred
    ax.HorizontalAlignment = xlCenter;  ax.VerticalAlignment = xlCenter;
    lab = sh.Range(sprintf('C%d', r));                  % the label: bold, dark red
    lab.Font.Bold = true;  lab.Font.Color = 192;        % 192 = RGB(192, 0, 0)
end
tbl = sh.Range(sprintf('A%d:J%d', rHdr, rHdr + n));
tbl.Borders.LineStyle = xlContinuous;  tbl.Borders.Weight = xlThin;

% ---- origin names merged over their rows ----
for g = 1:numel(groupFirst)
    rg = sh.Range(sprintf('A%d:A%d', rHdr + groupFirst(g), rHdr + groupLast(g)));
    rg.Merge();
    rg.HorizontalAlignment = xlCenter;  rg.VerticalAlignment = xlCenter;  rg.WrapText = true;
end

% ---- origin previews to the right of the header text, names above them ----
% Preview k spans the two columns of its name (E:F, then G:H) and is centred
% on them, with its top edge on the bottom of the name row.  Positions come
% from the column widths just set (a character is 7 px + 5 px of cell padding,
% and a point is 0.75 px), so they do not depend on what Excel reports for the
% cell geometry.
if ~isempty(pics)
    nP = numel(pics);
    if nP == 1, span = 4; else, span = 2; end  % E:H for one preview, E:F and G:H for two
    [boxW, boxH] = preview_box(nP);            % inches
    top0 = 20;                                 % row 1 holds the names
    bandH = preview_band() * 72;               % rows 2 to 9, in points
    for k = 1:nP
        first = 5 + 2 * (k - 1);               % column E for k = 1, G for k = 2
        left = 0;
        for c = 1:(first - 1), left = left + (widths(c) * 7 + 5) * 0.75; end
        spanW = 0;
        for c = first:(first + span - 1), spanW = spanW + (widths(c) * 7 + 5) * 0.75; end
        [picW, picH] = fit_in_box(picSizes(k, :), boxW, boxH);
        picW = picW * 72;  picH = picH * 72;   % points
        % centred on its columns and vertically within rows 2 to 9
        % msoFalse (0) = do not link, msoTrue (-1) = store in the workbook
        sh.Shapes.AddPicture(pics{k}, 0, -1, left + 0.5 * (spanW - picW), ...
                             top0 + 0.5 * (bandH - picH), picW, picH);
        c1 = col_letter(first);  c2 = col_letter(first + span - 1);
        lab = sh.Range(sprintf('%s1:%s1', c1, c2));
        lab.Merge();
        sh.Range(sprintf('%s1', c1)).Value = previews(k).name;
        lab.Font.Bold = true;  lab.HorizontalAlignment = xlCenter;  lab.VerticalAlignment = xlBottom;
    end
end

% ---- the unit-ratio sheet the formulas read, kept out of the way ----
su = wb.Sheets.Item('Unit ratios');
su.Range('A1').EntireColumn.ColumnWidth = 18;
su.Range('B1').EntireColumn.ColumnWidth = 9;
for c = 3:8
    su.Range(sprintf('%s1', col_letter(c))).EntireColumn.ColumnWidth = 12;
end
su.Range(sprintf('A%d:H%d', rHdr, rHdr)).Font.Bold = true;
ur = su.Range(sprintf('C%d:H%d', rHdr + 1, rHdr + n));
ur.NumberFormat = '0.000000';  ur.HorizontalAlignment = xlRight;
for k = 1:n
    for j = 1:6
        if any(rows(k).bold == j)
            su.Range(sprintf('%s%d', unitLetters(j), rHdr + k)).Font.Bold = true;
        end
    end
end
utbl = su.Range(sprintf('A%d:H%d', rHdr, rHdr + n));
utbl.Borders.LineStyle = xlContinuous;  utbl.Borders.Weight = xlThin;
su.Visible = 0;                                % hidden; the formulas still read it

sh.Activate();
sel = sh.Range('A1');  sel.Select();

% Release every interface object this function created; Excel stays alive
% (and keeps the file locked) while any of them are still referenced.
release_com(sel, utbl, ur, su, tbl, hdr, sh);
end


function s = col_letter(c)
%COL_LETTER  Column number -> Excel letters (A, B, ... Z, AA, ...).
s = '';
while c > 0
    r = mod(c - 1, 26);
    s = [char('A' + r) s]; %#ok<AGROW>
    c = floor((c - 1) / 26);
end
end


function export_png(path, rows, dec, head, previews)
%EXPORT_PNG  Rendered table (white background, black grid, bold reference
%   legs, merged origin cells), sized to the content.
fmt = sprintf('%%.%df', dec);
cols = [{'Origin', 'Axis', 'Label'}, arrayfun(@(j) sprintf('Leg %d', j), 1:6, 'Uni', false)];      % the Turn column is not exported
n = numel(rows);
labChars = max([numel('Label'), cellfun(@numel, {rows.label})]);
colW = [1.45 0.75 max(0.85, 0.092 * labChars + 0.2) 0.85 0.85 0.85 0.85 0.85 0.85];  % inches
rowH = 0.28;
% the header text spans the first four columns; the previews take two columns
% each and the legend the last one
textW = sum(colW(1:4));
maxChars = floor((textW - 0.15) / 0.062);
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
labelH = 0.2;
[boxW, boxH] = preview_box(numel(previews));
bandH = preview_band();                    % rows 2 to 9 of the workbook
if isempty(previews), pictH = 0; else, pictH = 0.12 + labelH + bandH; end
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
    if c >= 4 && c <= 9, col = legColors{c - 3}; else, col = 'k'; end
    text(ax, 0.5*(xE(c)+xE(c+1)), 0.5*(yE(1)+yE(2)), cols{c}, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'FontSize', 8.5, 'FontWeight', 'bold', 'Color', col);
end
% each preview spans two Leg columns (a single one spans all four) and is
% centred on them, its name directly above it and the picture centred
% vertically in the band below the names, from the same cropped image and the
% same box rules the workbook uses; the legend has the last column
yTop = figH - 0.12 - labelH;
[pics, picSizes] = render_previews(previews);
for k = 1:numel(previews)
    if numel(previews) == 1
        x0 = xE(5);  x1 = xE(9);                              % columns 5-8
    else
        x0 = xE(4 + 2 * (k - 1) + 1);  x1 = xE(4 + 2 * k + 1);  % 5-6, then 7-8
    end
    [skW, skH] = fit_in_box(picSizes(k, :), min(boxW, x1 - x0), boxH);
    skY = yTop - 0.5 * (bandH + skH);                         % centred in the band
    text(ax, 0.5 * (x0 + x1), yTop + 0.04, previews(k).name, 'FontSize', 8, ...
        'FontWeight', 'bold', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    axS = axes(f, 'Units', 'inches', 'Position', [0.5 * (x0 + x1) - 0.5 * skW, skY, skW, skH]);
    image(axS, imread(pics{k}));
    axis(axS, 'off');
end
for i = 1:numel(pics)
    if isfile(pics{i}), delete_file(pics{i}); end
end
legendX = 0.5 * (xE(end - 1) + xE(end));
for j = 1:6
    text(ax, legendX, yTop - (j - 1) * 0.24, sprintf('Leg %d', j), 'FontSize', 8.5, ...
        'FontWeight', 'bold', 'Color', legColors{j}, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
end
groupFirst = [];  groupLast = [];  prev = 0;
for k = 1:n
    r = rows(k);
    if r.origin ~= prev, groupFirst(end+1) = k; groupLast(end+1) = k; prev = r.origin; else, groupLast(end) = k; end %#ok<AGROW>
    yc = 0.5*(yE(k+1)+yE(k+2));
    text(ax, 0.5*(xE(2)+xE(3)), yc, r.axis, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', 'FontSize', 8.5);
    text(ax, 0.5*(xE(3)+xE(4)), yc, r.label, 'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', 'FontSize', 8.5, 'FontWeight', 'bold', 'Color', '#C00000');
    for j = 1:6
        if any(r.bold == j)
            % double bold: drawn twice, one pixel apart
            text(ax, xE(j+4) - 0.08, yc, sprintf(fmt, r.values(j)), 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'middle', 'FontSize', 8.5, 'FontWeight', 'bold');
            text(ax, xE(j+4) - 0.08 + 0.005, yc, sprintf(fmt, r.values(j)), 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'middle', 'FontSize', 8.5, 'FontWeight', 'bold');
        else
            text(ax, xE(j+4) - 0.08, yc, sprintf(fmt, r.values(j)), 'HorizontalAlignment', 'right', ...
                'VerticalAlignment', 'middle', 'FontSize', 8.5);
        end
    end
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
