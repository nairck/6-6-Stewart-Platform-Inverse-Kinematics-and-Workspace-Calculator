function origin_dialog(mainFig)
%ORIGIN_DIALOG  Modal list of origins / points of interest.
%
%   Rows are plain controls on the dialog background: a radio button (exactly
%   one selected), the name (1 to NAME_MAX characters, no apostrophe), the X / Y / Z
%   offset [mm] and the roll / pitch / yaw orientation [deg] of the frame
%   relative to Origin 1, both in the Origin 1 frame (angles about the
%   current roll/pitch/yaw axes).  Origin 1 is the reference: its offset and
%   orientation are locked at zero and it cannot be deleted.
%
%   The dialog is modal, so every other program window is blocked until
%   Confirm or Cancel. Nothing is applied here: Confirm validates the rows and
%   hands them to apply_origin; Cancel leaves the program untouched.

pinfo = get(mainFig, 'UserData');

d = dialog('Name', 'Origins / Points of Interest', 'WindowStyle', 'modal', ...
           'Resize', 'off', 'Visible', 'off');
setappdata(d, 'mainFig',  mainFig);
setappdata(d, 'origins',  pinfo.origins);
setappdata(d, 'active',   pinfo.origin_active);
setappdata(d, 'first',    true);
build(d);
set(d, 'Visible', 'on');
end


% =========================================================================
function build(d)
%BUILD  (Re)create every control from the dialog's appdata and fit the height.
NAME_MAX = 22;
MAX_ROWS = 12;
W = 740;  M = 15;  ROW_H = 26;  GAP = 8;
cRadio = 20;  cName = 178;  cOff = 74;  cGap = 8;
KEYS = {'dx', 'dy', 'dz', 'roll', 'pitch', 'yaw'};
origins = getappdata(d, 'origins');
active  = getappdata(d, 'active');
N = numel(origins);

hIntro = 48;  hHdr = 16;  hRows = N*ROW_H;  hBtn = 28;  hNote = 32;
H = M + hIntro + 6 + hHdr + 4 + hRows + GAP + hBtn + GAP + hNote + GAP + hBtn + M;

delete(allchild(d));
if getappdata(d, 'first')
    set(d, 'Position', [0 0 W H]);
    movegui(d, 'center');
    setappdata(d, 'first', false);
else
    pos = get(d, 'Position');                       % keep the top edge where it is
    set(d, 'Position', [pos(1), pos(2) + pos(4) - H, W, H]);
end
bg = get(d, 'Color');

% --- intro ---
y = H - M - hIntro;
uicontrol(d, 'Style', 'text', 'Position', [M y W-2*M hIntro], 'FontSize', 9, ...
    'HorizontalAlignment', 'left', 'BackgroundColor', bg, 'String', ...
    {'Select the origin (point of interest) that the 6-DOF pose, the System Illustration and the workspace'; ...
     'analyses are referenced to. An origin is a frame: its X, Y, Z offset [mm] and its roll, pitch, yaw'; ...
     'orientation [°] relative to Origin 1, both in the Origin 1 frame (angles about the current rpy axes).'});

% --- column headers ---
y = y - 6 - hHdr;
xRadio = M;  xName = xRadio + cRadio + cGap;
xs = xName + cName + cGap + (0:5) * (cOff + cGap);           % the six value columns
hdr = {sprintf('Name (max %d chars)', NAME_MAX), xName, cName; 'X [mm]', xs(1), cOff; 'Y [mm]', xs(2), cOff; ...
       'Z [mm]', xs(3), cOff; 'Roll [°]', xs(4), cOff; 'Pitch [°]', xs(5), cOff; 'Yaw [°]', xs(6), cOff};
for k = 1:size(hdr, 1)
    uicontrol(d, 'Style', 'text', 'Position', [hdr{k,2} y hdr{k,3} hHdr], ...
        'String', hdr{k,1}, 'FontWeight', 'bold', 'FontSize', 9, ...
        'HorizontalAlignment', 'center', 'BackgroundColor', bg);
end

% --- rows (inside a button group so exactly one radio is ever selected) ---
y = y - 4 - hRows;
grp = uibuttongroup(d, 'Units', 'pixels', 'Position', [M y W-2*M hRows], ...
    'BorderType', 'none', 'BackgroundColor', bg, ...
    'SelectionChangedFcn', @(~, ~) refresh_buttons(d));
rows = struct('radio', {}, 'name', {}, 'dx', {}, 'dy', {}, 'dz', {}, 'roll', {}, 'pitch', {}, 'yaw', {});
for i = 1:N
    ry = (N - i)*ROW_H;                             % relative to the group
    isRef = (i == 1);
    r.radio = uicontrol(grp, 'Style', 'radiobutton', 'Position', [xRadio-M ry+4 cRadio 18], ...
        'BackgroundColor', bg, 'UserData', i, 'Value', i == active, ...
        'TooltipString', 'Use this origin for the pose, illustration and workspaces');
    r.name = uicontrol(grp, 'Style', 'edit', 'Position', [xName-M ry+2 cName ROW_H-4], ...
        'String', origins(i).name, 'HorizontalAlignment', 'left', 'BackgroundColor', 'white', ...
        'TooltipString', sprintf('Origin name, 1 to %d characters', NAME_MAX));
    if isRef
        set(r.name, 'TooltipString', ...
            'Reference origin (base/platform joints are entered in this frame). It can be renamed but not deleted.');
    end
    for k = 1:6
        h = uicontrol(grp, 'Style', 'edit', 'Position', [xs(k)-M ry+2 cOff ROW_H-4], ...
            'String', sprintf('%.3f', origin_value(origins(i), KEYS{k})), 'HorizontalAlignment', 'center', ...
            'BackgroundColor', 'white');
        if isRef
            set(h, 'Enable', 'off', 'TooltipString', ...
                'Origin 1 is the reference frame: its offset and orientation are always zero');
        end
        r.(KEYS{k}) = h;
    end
    rows(i) = r;
end
setappdata(d, 'rows', rows);

% --- add / delete ---
y = y - GAP - hBtn;
hAdd = uicontrol(d, 'Style', 'pushbutton', 'Position', [M y 220 hBtn], ...
    'String', 'Add New Origin / Point of Interest', 'Callback', @(~, ~) on_add(d));
hDel = uicontrol(d, 'Style', 'pushbutton', 'Position', [M+228 y 120 hBtn], ...
    'String', 'Delete Selected', 'Callback', @(~, ~) on_delete(d), 'TooltipString', ...
    'Remove the origin whose radio button is selected (Origin 1 is the reference and cannot be deleted)');
if N >= MAX_ROWS
    set(hAdd, 'Enable', 'off', 'TooltipString', sprintf('Maximum of %d origins reached', MAX_ROWS));
else
    set(hAdd, 'TooltipString', 'Add a new point of interest (frame relative to Origin 1)');
end
setappdata(d, 'hDel', hDel);

% --- note ---
y = y - GAP - hNote;
uicontrol(d, 'Style', 'text', 'Position', [M y W-2*M hNote], 'FontSize', 8, ...
    'FontAngle', 'italic', 'ForegroundColor', [0.4 0.4 0.4], 'BackgroundColor', bg, ...
    'HorizontalAlignment', 'left', 'String', ...
    {'Confirm re-expresses every joint coordinate, the old and new poses, the illustration and all later'; ...
     'workspace analyses about the selected origin. Cancel changes nothing.'});

% --- confirm / cancel ---
y = y - GAP - hBtn;
uicontrol(d, 'Style', 'pushbutton', 'Position', [W-M-100-8-100 y 100 hBtn], ...
    'String', 'Confirm', 'Callback', @(~, ~) on_confirm(d));
uicontrol(d, 'Style', 'pushbutton', 'Position', [W-M-100 y 100 hBtn], ...
    'String', 'Cancel', 'Callback', @(~, ~) delete(d));

refresh_buttons(d);
end


% =========================================================================
function v = origin_value(o, name)
if isfield(o, name) && ~isempty(o.(name))
    v = o.(name);
else
    v = 0;
end
end


function idx = selected_index(d)
rows = getappdata(d, 'rows');
idx = 1;
for i = 1:numel(rows)
    if get(rows(i).radio, 'Value')
        idx = i;
        return;
    end
end
end


function refresh_buttons(d)
rows = getappdata(d, 'rows');
hDel = getappdata(d, 'hDel');
if selected_index(d) ~= 1 && numel(rows) > 1
    set(hDel, 'Enable', 'on');
else
    set(hDel, 'Enable', 'off');
end
end


function [origins, active, err] = collect(d)
%COLLECT  Read the rows back (raw text; validation is done by the caller).
rows = getappdata(d, 'rows');
origins = struct('name', {}, 'dx', {}, 'dy', {}, 'dz', {}, 'roll', {}, 'pitch', {}, 'yaw', {});
err = '';
KEYS = {'dx', 'dy', 'dz', 'roll', 'pitch', 'yaw'};
for i = 1:numel(rows)
    o.name = strtrim(get(rows(i).name, 'String'));
    if iscell(o.name), o.name = ''; end
    for k = 1:6
        if i == 1
            o.(KEYS{k}) = 0;
        else
            o.(KEYS{k}) = str2double(get(rows(i).(KEYS{k}), 'String'));
        end
    end
    origins(i) = o;
end
active = selected_index(d);
end


function [ok, msg] = validate_rows(origins)
NAME_MAX = 22;
ok = false;
for i = 1:numel(origins)
    nm = origins(i).name;
    if isempty(nm)
        msg = sprintf('Row %d: please enter an origin name (1 to %d characters).', i, NAME_MAX);
        return;
    end
    if numel(nm) > NAME_MAX
        msg = sprintf('Row %d: names are limited to %d characters.', i, NAME_MAX);
        return;
    end
    if any(nm == '''')
        msg = sprintf('Row %d: the apostrophe character is not allowed in a name.', i);
        return;
    end
    if any(isnan([origins(i).dx, origins(i).dy, origins(i).dz, origins(i).roll, origins(i).pitch, origins(i).yaw]))
        msg = sprintf('Row %d: the offsets and angles must be numbers.', i);
        return;
    end
end
ok = true;
msg = '';
end


function on_add(d)
[origins, ~, ~] = collect(d);                       % keep any edits typed so far
n = numel(origins) + 1;
origins(n) = struct('name', sprintf('Origin %d', n), 'dx', 0, 'dy', 0, 'dz', 0, 'roll', 0, 'pitch', 0, 'yaw', 0);
setappdata(d, 'origins', origins);
setappdata(d, 'active', n);                         % select the new row
build(d);
end


function on_delete(d)
[origins, sel, ~] = collect(d);
if sel == 1 || numel(origins) <= 1
    return;                                         % Origin 1 is never deleted
end
origins(sel) = [];
setappdata(d, 'origins', origins);
setappdata(d, 'active', max(1, sel - 1));           % select the row above
build(d);
end


function on_confirm(d)
[origins, active, ~] = collect(d);
[ok, msg] = validate_rows(origins);
if ~ok
    uiwait(errordlg(msg, 'Invalid origin', 'modal'));
    return;
end
for i = 1:numel(origins)
    for k = {'dx', 'dy', 'dz', 'roll', 'pitch', 'yaw'}
        origins(i).(k{1}) = round(origins(i).(k{1}), 3);
    end
end
mainFig = getappdata(d, 'mainFig');
delete(d);
set(0, 'CurrentFigure', mainFig);
apply_origin(mainFig, origins, active);
end
