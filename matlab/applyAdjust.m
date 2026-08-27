function applyAdjust(mainFig,field,editHndl,d2)
    v = round(str2double(strtrim(get(editHndl,'String'))), 3);   % typed or pasted, 3 decimals
    if isnan(v)
        errordlg('Please enter a numeric value.','Invalid Input');
        return;
    end

    % grab & update the running total on mainFig
    key  = [field '_totalOffset'];
    prev = getappdata(mainFig,key);
    if isempty(prev), prev = 0; end
    total = prev + v;
    setappdata(mainFig,key,total);

    % apply to the six controls
    pi = get(mainFig,'UserData');
    % field is xsi/ysi/zsi (base) or xmi/ymi/zmi (platform)
    switch field
      case 'xsi', names = arrayfun(@(k)sprintf('base%dx',k),1:6,'Uni',false);
      case 'ysi', names = arrayfun(@(k)sprintf('base%dy',k),1:6,'Uni',false);
      case 'zsi', names = arrayfun(@(k)sprintf('base%dz',k),1:6,'Uni',false);
      case 'xmi', names = arrayfun(@(k)sprintf('plat%dx',k),1:6,'Uni',false);
      case 'ymi', names = arrayfun(@(k)sprintf('plat%dy',k),1:6,'Uni',false);
      case 'zmi', names = arrayfun(@(k)sprintf('plat%dz',k),1:6,'Uni',false);
    end
    for fn = names
        h   = pi.(fn{1});
        old = str2double(get(h,'String'));
        set(h,'String',sprintf('%.3f',old+v));
    end

    delete(d2);
    solve_inverse();
end
