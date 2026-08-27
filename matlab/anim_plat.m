function anim_plat(plat_coords)
% ANIM_PLAT   Smoothly animate the platform moving to new coordinates
%
%   anim_plat(plat_coords) reads the existing leg and platform‑edge plot
%   handles from the figure’s UserData, updates each leg’s base endpoint
%   if the GUI base joints moved, then interpolates each segment in N
%   steps (default 40) to the new platform coordinates.


    %── Retrieve plot‐handles ────────────────────────────────────────
    plotinfo = get(gcf,'UserData');
    if isfield(plotinfo, 'sketch_disp'), D = plotinfo.sketch_disp; else, D = eye(3); end   % see draw_plat.m
    legH   = arrayfun(@(k) plotinfo.(sprintf('p%d',k)),   1:6);
    platH  = arrayfun(@(k) plotinfo.(sprintf('p%d',k+6)), 1:6);
    baseH  = arrayfun(@(k) plotinfo.(sprintf('p%d',k+12)),1:3);  % p13,p14,p15
    
    %── Read updated base joint positions ───────────────────────────
    base_x  = arrayfun(@(i) str2double(get(plotinfo.(sprintf('base%dx',i)),'String')),1:6);
    base_y  = arrayfun(@(i) str2double(get(plotinfo.(sprintf('base%dy',i)),'String')),1:6);
    base_z  = arrayfun(@(i) str2double(get(plotinfo.(sprintf('base%dz',i)),'String')),1:6);
    basePts = D * [base_x; base_y; base_z];  % 3×6 (each base joint has its own Z), display frame

    %── Cache old leg & platform data ──────────────────────────────
    oldLegX = zeros(6,2); oldLegY = zeros(6,2); oldLegZ = zeros(6,2);
    oldPlatX= zeros(6,2); oldPlatY= zeros(6,2); oldPlatZ= zeros(6,2);
    for i = 1:6
        d = get(legH(i), {'XData','YData','ZData'});
        oldLegX(i,:) = d{1};
        oldLegY(i,:) = d{2};
        oldLegZ(i,:) = d{3};
        d2 = get(platH(i), {'XData','YData','ZData'});
        oldPlatX(i,:) = d2{1};
        oldPlatY(i,:) = d2{2};
        oldPlatZ(i,:) = d2{3};
    end

    %── Override leg base endpoints with current GUI basePts ────────
    oldLegX(:,1) = basePts(1,:)';
    oldLegY(:,1) = basePts(2,:)';
    oldLegZ(:,1) = basePts(3,:)';

    %── Parse new platform points into 6×3 array ───────────────────
    newPts = (D * reshape(plat_coords,3,6))';  % rows = [x y z] for each corner, display frame

    %── Animate interpolation ──────────────────────────────────────
    nSteps = 40;
    baseEdges = [2 3; 4 5; 6 1];
    for step = 1:nSteps
        t = step / nSteps;
        
         %—— first, update base edges from the GUI controls ——
        bx     = arrayfun(@(i) str2double(get(plotinfo.(sprintf('base%dx',i)),'String')),1:6);
        by     = arrayfun(@(i) str2double(get(plotinfo.(sprintf('base%dy',i)),'String')),1:6);
        bz     = arrayfun(@(i) str2double(get(plotinfo.(sprintf('base%dz',i)),'String')),1:6);
        bp     = D * [bx; by; bz];
        for e = 1:3
            i1 = baseEdges(e,1); i2 = baseEdges(e,2);
            set(baseH(e), ...
                'XData', bp(1,[i1 i2]), ...
                'YData', bp(2,[i1 i2]), ...
                'ZData', bp(3,[i1 i2])  ...
            );
        end
        
        % legs
        for i = 1:6
            set(legH(i), ...
                'XData',[oldLegX(i,1), oldLegX(i,2)+(newPts(i,1)-oldLegX(i,2))*t], ...
                'YData',[oldLegY(i,1), oldLegY(i,2)+(newPts(i,2)-oldLegY(i,2))*t], ...
                'ZData',[oldLegZ(i,1), oldLegZ(i,2)+(newPts(i,3)-oldLegZ(i,2))*t]  ...
            );
        end
        % platform edges
        for i = 1:6
            j = mod(i,6) + 1;
            set(platH(i), ...
                'XData',[ oldPlatX(i,1)+(newPts(i,1)-oldPlatX(i,1))*t, ...
                          oldPlatX(i,2)+(newPts(j,1)-oldPlatX(i,2))*t ], ...
                'YData',[ oldPlatY(i,1)+(newPts(i,2)-oldPlatY(i,1))*t, ...
                          oldPlatY(i,2)+(newPts(j,2)-oldPlatY(i,2))*t ], ...
                'ZData',[ oldPlatZ(i,1)+(newPts(i,3)-oldPlatZ(i,1))*t, ...
                          oldPlatZ(i,2)+(newPts(j,3)-oldPlatZ(i,2))*t ]  ...
            );
        end
        drawnow;
    end

    %── Save handles back (unchanged) ───────────────────────────────
    set(gcf,'UserData',plotinfo);
end
