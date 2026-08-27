function refresh_origin_ui(mainFig)
%REFRESH_ORIGIN_UI  Update the "Current Origin" button and the Edit-ZPD lock.
%
%   The zero-displacement coordinates may only be edited in the Origin 1 frame
%   (the frame they were entered in). For any other origin the "Edit
%   Zero-Displacement Coordinates" toggle is switched off (locking the fields,
%   exactly as if the user had clicked it) and
%   then disabled. The +/- column adjusters stay available in every frame.

pinfo = get(mainFig, 'UserData');
name = pinfo.origins(pinfo.origin_active).name;
% "Current Origin:" plus the name on one or two further lines (names are up
% to 22 characters); the font is then shrunk to fit the button.
lines = [{'Current Origin:'}, wrap_button_name(name)];
fit_button_font(pinfo.origin_but, lines, 112, 52);

% The Edit-ZPD button explains itself while disabled (second, centred line).
if pinfo.origin_active == 1
    set(pinfo.editzpd_but, 'Enable', 'on');
    fit_button_font(pinfo.editzpd_but, {'Edit Zero-Displacement Coordinates'}, 349, 50, 11, 7);
else
    if get(pinfo.editzpd_but, 'Value')
        set(pinfo.editzpd_but, 'Value', 0);
        set(0, 'CurrentFigure', mainFig);
        edit_zpd();                       % locks the fields
    end
    set(pinfo.editzpd_but, 'Enable', 'off');
    fit_button_font(pinfo.editzpd_but, ...
        {'Edit Zero-Displacement Coordinates'; '(must be at primary origin to edit)'}, 349, 50, 11, 7);
end
end
