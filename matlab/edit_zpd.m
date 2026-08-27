function edit_zpd()
%EDIT_ZPD  Lock / unlock the zero-displacement configuration fields.
%   Every base and platform joint has its own X, Y, Z box; together with the
%   ZPD leg length they are editable only while the toggle is on.
    pi = get(gcf,'UserData');
    editing = logical(get(pi.editzpd_but,'Value'));

    baseFields = arrayfun(@(i) {sprintf('base%dx',i), sprintf('base%dy',i), sprintf('base%dz',i)}, 1:6, 'Uni',false);
    platFields = arrayfun(@(i) {sprintf('plat%dx',i), sprintf('plat%dy',i), sprintf('plat%dz',i)}, 1:6, 'Uni',false);
    allFields = [ baseFields{:}, platFields{:}, {'zpdLegLength'} ];

    if ~editing
        cellfun(@(f) set(pi.(f),'Enable','off'), allFields);
    else
        cellfun(@(f) set(pi.(f),'Enable','on'), allFields);
    end
end
