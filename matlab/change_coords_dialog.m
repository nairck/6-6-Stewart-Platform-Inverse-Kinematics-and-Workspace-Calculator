function change_coords_dialog(mainFig)
%CHANGE_COORDS_DIALOG  Modal right-handed relabelling of the X, Y, Z axes.
%
%   One row per CURRENT axis ("Current X ->", "Current Y ->", "Current Z ->")
%   with six radio buttons (+X, -X, +Y, -Y, +Z, -Z); exactly one per row.  The
%   right-hand rule is enforced downward: changing the Current-X row disables
%   the two Current-Y choices parallel to it (moving that row's selection to
%   the next axis if it became invalid), and the Current-Z row is always the
%   cross product of the two rows above (its only enabled choice).  Rows above
%   a change are never touched.
%
%   Below the rows the sketch's coordinate triad is drawn twice in its default
%   view: the current X, Y, Z and, after an arrow, the new frame's positive X,
%   Y, Z pointing where they physically lie in that same view (a current axis
%   mapped to a negative new axis makes the new arrow point the other way).
%   The view itself is never changed.
%
%   A second section assigns the rotation angles to axes: "Roll about",
%   "Pitch about", "Yaw about" with X / Y / Z radios.  Only the right-handed
%   cyclic assignments exist (XYZ, YZX, ZXY), enforced downward: the roll row
%   is free, the pitch row is the next axis and the yaw row the one after
%   (their only enabled choices).  The axes refer to the NEW labels chosen
%   above.
%
%   Confirm hands the mapping to apply_axis_map and the assignment to
%   apply_rpy_axes; Close leaves everything untouched.

OPTIONS = {'+X', '-X', '+Y', '-Y', '+Z', '-Z'};
W = 640;  M = 15;  ROW_H = 26;  GAP = 8;  BTN_H = 28;
% a text control clips rather than wraps, so each block is sized for its own
% number of lines (about 19 px a line at font size 9) plus a little padding
hIntro = 4 * 19 + 8;  hTriad = 150;  hNote = 18;  hRpyIntro = 2 * 19 + 6;  hCap = 18;
H = M + hIntro + GAP + 3*ROW_H + GAP + hCap + hTriad + GAP + hRpyIntro + GAP + 3*ROW_H + GAP + hNote + GAP + BTN_H + M;
pinfoMain = get(mainFig, 'UserData');
rpyInitial = rpy_axes_of(pinfoMain);

d = dialog('Name', 'Change Coordinate Axes', 'WindowStyle', 'modal', ...
           'Resize', 'off', 'Visible', 'off', 'Position', [0 0 W H]);
movegui(d, 'center');
bg = get(d, 'Color');
setappdata(d, 'mainFig', mainFig);
setappdata(d, 'OPTIONS', OPTIONS);
setappdata(d, 'updating', false);

% --- intro ---
y = H - M - hIntro;
uicontrol(d, 'Style', 'text', 'Position', [M y W-2*M hIntro], 'FontSize', 9, ...
    'HorizontalAlignment', 'left', 'BackgroundColor', bg, 'String', ...
    {'Relabel the coordinate axes. For each current axis choose the signed axis it becomes; the'; ...
     'combination is kept right-handed automatically (the Current Z row is always the cross'; ...
     'product of the two rows above it). Confirm remaps every joint coordinate, the poses, the'; ...
     'search limits and the origins. The field labels in the program stay X, Y, Z.'});

% --- rows: label + 6 radio buttons each, inside a button group per row ---
letters = 'XYZ';
groups = gobjects(1,3);
radios = gobjects(3, numel(OPTIONS));
for r = 1:3
    y = y - ROW_H - (r == 1) * GAP;
    uicontrol(d, 'Style', 'text', 'Position', [M y+2 90 ROW_H-6], 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'right', 'BackgroundColor', bg, ...
        'String', sprintf('Current %s  ->', letters(r)));
    groups(r) = uibuttongroup(d, 'Units', 'pixels', 'Position', [M+100 y W-2*M-100 ROW_H], ...
        'BorderType', 'none', 'BackgroundColor', bg, ...
        'SelectionChangedFcn', @(~, ~) on_row_changed(d, r));
    for c = 1:numel(OPTIONS)
        radios(r, c) = uicontrol(groups(r), 'Style', 'radiobutton', ...
            'Position', [(c-1)*62 4 60 18], 'String', OPTIONS{c}, 'BackgroundColor', bg, ...
            'UserData', c);
    end
end
setappdata(d, 'radios', radios);

% --- triads: 'Current' / 'New' captions on their own row, clear of the rows
% above, then the two triads with an arrow between them ---
y = y - GAP - hCap;
uicontrol(d, 'Style', 'text', 'Position', [M+30 y 220 hCap], 'String', 'Current', 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'BackgroundColor', bg);
uicontrol(d, 'Style', 'text', 'Position', [W-M-250 y 220 hCap], 'String', 'New', 'FontWeight', 'bold', ...
    'HorizontalAlignment', 'center', 'BackgroundColor', bg);
y = y - hTriad;
axCur = axes('Parent', d, 'Units', 'pixels', 'Position', [M+30 y 220 hTriad], 'Visible', 'off');
axNew = axes('Parent', d, 'Units', 'pixels', 'Position', [W-M-250 y 220 hTriad], 'Visible', 'off');
uicontrol(d, 'Style', 'text', 'Position', [W/2-20 y+hTriad/2-12 40 26], 'String', '->', ...
    'FontSize', 18, 'FontWeight', 'bold', 'BackgroundColor', bg, 'HorizontalAlignment', 'center');
setappdata(d, 'axCur', axCur);
setappdata(d, 'axNew', axNew);
% Fixed at the sketch's nominal view: no rotation, pan or zoom in this window
% (only the arrows of the "New" triad change with the selection).
rotate3d(d, 'off');
for ax = [axCur, axNew]
    try
        disableDefaultInteractivity(ax);
    catch
    end
    set(ax, 'HitTest', 'off');
end

% --- rotation-angle axes ---
y = y - GAP - hRpyIntro;
uicontrol(d, 'Style', 'text', 'Position', [M y W-2*M hRpyIntro], 'FontSize', 9, ...
    'HorizontalAlignment', 'left', 'BackgroundColor', bg, 'String', ...
    {'Rotation angles: choose the axis roll rotates about; pitch and yaw follow the right-hand'; ...
     'rule (the next axes in cyclic order X, Y, Z). The axes are the new labels chosen above.'});
angles = {'Roll', 'Pitch', 'Yaw'};
axisLetters = 'XYZ';
rpyGroups = gobjects(1,3);
rpyRadios = gobjects(3, 3);
for r = 1:3
    y = y - ROW_H;
    uicontrol(d, 'Style', 'text', 'Position', [M y+2 90 ROW_H-6], 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'right', 'BackgroundColor', bg, ...
        'String', sprintf('%s about  ->', angles{r}));
    rpyGroups(r) = uibuttongroup(d, 'Units', 'pixels', 'Position', [M+100 y W-2*M-100 ROW_H], ...
        'BorderType', 'none', 'BackgroundColor', bg, ...
        'SelectionChangedFcn', @(~, ~) on_rpy_changed(d, r));
    for c = 1:3
        rpyRadios(r, c) = uicontrol(rpyGroups(r), 'Style', 'radiobutton', ...
            'Position', [(c-1)*62 4 60 18], 'String', axisLetters(c), 'BackgroundColor', bg);
    end
end
setappdata(d, 'rpyRadios', rpyRadios);

% --- note + buttons ---
y = y - GAP - hNote;
uicontrol(d, 'Style', 'text', 'Position', [M y W-2*M hNote], 'FontSize', 8, ...
    'FontAngle', 'italic', 'ForegroundColor', [0.4 0.4 0.4], 'BackgroundColor', bg, ...
    'HorizontalAlignment', 'left', 'String', 'Close discards the selection and changes nothing.');
y = y - GAP - BTN_H;
uicontrol(d, 'Style', 'pushbutton', 'Position', [W-M-100-8-100 y 100 BTN_H], ...
    'String', 'Confirm', 'Callback', @(~, ~) on_confirm(d));
uicontrol(d, 'Style', 'pushbutton', 'Position', [W-M-100 y 100 BTN_H], ...
    'String', 'Close', 'Callback', @(~, ~) delete(d));

% identity mapping to start with (+X, +Y, +Z), then enforce the rule downward
setappdata(d, 'updating', true);
set(radios(1,1), 'Value', 1);
set(radios(2,3), 'Value', 1);
set(radios(3,5), 'Value', 1);
setappdata(d, 'updating', false);
enforce(d, 0);
% current angle assignment to start with
setappdata(d, 'updating', true);
axisLetters = 'XYZ';
set(rpyRadios(1, find(axisLetters == rpyInitial(1), 1)), 'Value', 1);
setappdata(d, 'updating', false);
enforce_rpy(d);
set(d, 'Visible', 'on');
end


% =========================================================================
function ch = rpy_selected(d, r)
rpyRadios = getappdata(d, 'rpyRadios');
axisLetters = 'XYZ';
ch = 'X';
for c = 1:3
    if get(rpyRadios(r, c), 'Value')
        ch = axisLetters(c);
        return;
    end
end
end


function on_rpy_changed(d, r)
if getappdata(d, 'updating') || r ~= 1, return; end
enforce_rpy(d);
end


function enforce_rpy(d)
%ENFORCE_RPY  Pitch and yaw are the next axes after the roll axis, cyclically.
rpyRadios = getappdata(d, 'rpyRadios');
axisLetters = 'XYZ';
setappdata(d, 'updating', true);
k = find(axisLetters == rpy_selected(d, 1), 1);
offs = [1, 2];
for row = 2:3
    ch = axisLetters(mod(k - 1 + offs(row - 1), 3) + 1);
    for c = 1:3
        if axisLetters(c) == ch
            set(rpyRadios(row, c), 'Value', 1, 'Enable', 'on');
        else
            set(rpyRadios(row, c), 'Enable', 'off');
        end
    end
end
setappdata(d, 'updating', false);
end


% =========================================================================
function lbl = selected(d, r)
radios = getappdata(d, 'radios');
OPTIONS = getappdata(d, 'OPTIONS');
lbl = '';
for c = 1:size(radios, 2)
    if get(radios(r, c), 'Value')
        lbl = OPTIONS{c};
        return;
    end
end
end


function select(d, r, lbl)
radios = getappdata(d, 'radios');
OPTIONS = getappdata(d, 'OPTIONS');
c = find(strcmp(OPTIONS, lbl), 1);
set(radios(r, c), 'Value', 1);
end


function on_row_changed(d, r)
if getappdata(d, 'updating'), return; end
enforce(d, r);
end


function enforce(d, fromRow)
%ENFORCE  Re-establish the right-hand rule for the rows BELOW fromRow.
radios = getappdata(d, 'radios');
OPTIONS = getappdata(d, 'OPTIONS');
setappdata(d, 'updating', true);
vx = selected(d, 1);
if fromRow <= 1
    % Current-Y row: choices parallel to the Current-X choice are impossible;
    % if the selection became parallel move it to the next axis (X->Y->Z->X).
    vy = selected(d, 2);
    if isempty(vy) || vy(2) == vx(2)
        letters = 'XYZ';
        k = find(letters == vx(2), 1);
        vy = ['+' letters(mod(k, 3) + 1)];
        select(d, 2, vy);
    end
    for c = 1:numel(OPTIONS)
        if OPTIONS{c}(2) == vx(2)
            set(radios(2, c), 'Enable', 'off');
        else
            set(radios(2, c), 'Enable', 'on');
        end
    end
end
vy = selected(d, 2);
% Current-Z row: fully determined by the cross product.
vz = axis_label(cross(axis_vector(vx), axis_vector(vy)));
select(d, 3, vz);
for c = 1:numel(OPTIONS)
    if strcmp(OPTIONS{c}, vz)
        set(radios(3, c), 'Enable', 'on');
    else
        set(radios(3, c), 'Enable', 'off');
    end
end
setappdata(d, 'updating', false);
draw_triads(d, {vx, vy, vz});
end


function draw_triads(d, newLabels)
axCur = getappdata(d, 'axCur');
axNew = getappdata(d, 'axNew');
% rows of M are the current-frame directions of the new X, Y, Z axes
M = axis_map_matrix(newLabels{1}, newLabels{2}, newLabels{3});
draw_triad(axCur, eye(3));
draw_triad(axNew, M);
end


function draw_triad(ax, dirs)
% Same triad as draw_plat.m (three arrows from the origin, letter at each
% tip) in the sketch's default view([-30,20]).  Row j of dirs is the direction
% the X / Y / Z arrow points along, in the axes' own coordinates, so a
% relabelled frame's positive axes are drawn where they physically point
% (a flipped axis points the opposite way) without changing the view.
cla(ax); hold(ax, 'on');
a = 1;
letters = {'X', 'Y', 'Z'};
for j = 1:3
    tip = a * dirs(j, :);
    plot3(ax, [0 tip(1)], [0 tip(2)], [0 tip(3)], '-k', 'LineWidth', 1);
    arrow_head(ax, tip, dirs(j, :), a, 'k');
    lp = tip * 1.28;      % letter beyond the tip along the arrow, clear of the arrowhead
    text(ax, lp(1), lp(2), lp(3), letters{j}, 'FontSize', 11, ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
end
axis(ax, 'equal', 'off');
% symmetric limits so a reversed arrow has the same room as a forward one;
% identical limits on both triads keep the two views the same
xlim(ax, [-1.35 1.35]); ylim(ax, [-1.35 1.35]); zlim(ax, [-1.35 1.35]);
view(ax, [-30, 20]);
hold(ax, 'off');
end


function on_confirm(d)
labels = {selected(d, 1), selected(d, 2), selected(d, 3)};
try
    M = axis_map_matrix(labels{1}, labels{2}, labels{3});
catch
    uiwait(errordlg('The selected combination is not right-handed.', 'Invalid mapping', 'modal'));
    return;
end
rpy = [rpy_selected(d, 1), rpy_selected(d, 2), rpy_selected(d, 3)];
if ~any(strcmp(rpy, {'XYZ', 'YZX', 'ZXY'}))
    uiwait(errordlg('The roll / pitch / yaw axes are not a right-handed cyclic set.', 'Invalid angle axes', 'modal'));
    return;
end
mainFig = getappdata(d, 'mainFig');
delete(d);
set(0, 'CurrentFigure', mainFig);
% first the axis relabelling (in the current angle assignment), then the new
% angle assignment, expressed in the relabelled axes
apply_axis_map(mainFig, M, labels);
apply_rpy_axes(mainFig, rpy);
end
