function draw_reachable_workspace_spherical(scaler, plotinfo, homeNewOld)
fprintf('Working on reachable workspace...\n')
tStart = tic;
set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'off');
set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'off');
d = findall(0, 'Type', 'figure', 'Name', 'Draw Reachable Workspace Progress');
if isempty(d) || ~all(isvalid(d))
    disp('Computation cancelled by user.');
    set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'on');
    set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'on');
    return;
end



if (scaler ~= 100)
    rpyAxes = rpy_axes_of(plotinfo);          % roll/pitch/yaw axes assignment
    % The 3D window keeps the sketch's "up": it is viewed through the sketch's
    % display frame D, stored with the data (see frame_view.m).
    if isfield(plotinfo, 'sketch_disp'), view_frame = diag([-1 -1 1]) * plotinfo.sketch_disp; else, view_frame = eye(3); end   % unturned sketch frame
    rpy_axes = rpyAxes;
    zpdLegLength = str2double(get(plotinfo.zpdLegLength, 'String'));
    leg_lower_limit = str2double(get(plotinfo.jointmin, 'String'));
    leg_upper_limit = str2double(get(plotinfo.jointmax, 'String'));
    x_lower_limit = str2double(get(plotinfo.pxmin, 'String'));
    x_upper_limit = str2double(get(plotinfo.pxmax, 'String'));
    y_lower_limit = str2double(get(plotinfo.pymin, 'String'));
    y_upper_limit = str2double(get(plotinfo.pymax, 'String'));
    z_lower_limit = str2double(get(plotinfo.pzmin, 'String'));
    z_upper_limit = str2double(get(plotinfo.pzmax, 'String'));
    xsi = cellfun(@(h) str2double(get(h, 'String')), {plotinfo.base1x, plotinfo.base2x, plotinfo.base3x, plotinfo.base4x, plotinfo.base5x, plotinfo.base6x});
    ysi = cellfun(@(h) str2double(get(h, 'String')), {plotinfo.base1y, plotinfo.base2y, plotinfo.base3y, plotinfo.base4y, plotinfo.base5y, plotinfo.base6y});
    zsi = cellfun(@(h) str2double(get(h, 'String')), {plotinfo.base1z, plotinfo.base2z, plotinfo.base3z, plotinfo.base4z, plotinfo.base5z, plotinfo.base6z});
    xmi = cellfun(@(h) str2double(get(h, 'String')), {plotinfo.plat1x, plotinfo.plat2x, plotinfo.plat3x, plotinfo.plat4x, plotinfo.plat5x, plotinfo.plat6x});
    ymi = cellfun(@(h) str2double(get(h, 'String')), {plotinfo.plat1y, plotinfo.plat2y, plotinfo.plat3y, plotinfo.plat4y, plotinfo.plat5y, plotinfo.plat6y});
    zmi = cellfun(@(h) str2double(get(h, 'String')), {plotinfo.plat1z, plotinfo.plat2z, plotinfo.plat3z, plotinfo.plat4z, plotinfo.plat5z, plotinfo.plat6z});
    if (homeNewOld == 1)    % new pose values 'roll','pitch','yaw','Pxval','Pyval','Pzval', ...
        rollp  = str2double(get(plotinfo.roll,  'String'));     pitchp  = str2double(get(plotinfo.pitch,  'String'));    yawp = str2double(get(plotinfo.yaw, 'String'));
        xp = str2double(get(plotinfo.Pxval, 'String'));         yp   = str2double(get(plotinfo.Pyval,   'String'));       zp   = str2double(get(plotinfo.Pzval,   'String'));
    elseif (homeNewOld == 2)    % old pose values  'roll_old','pitch_old','yaw_old','Pxval_old','Pyval_old','Pzval_old', ...
        rollp  = str2double(get(plotinfo.roll_old,  'String'));     pitchp  = str2double(get(plotinfo.pitch_old,  'String'));    yawp = str2double(get(plotinfo.yaw_old, 'String'));
        xp = str2double(get(plotinfo.Pxval_old, 'String'));         yp   = str2double(get(plotinfo.Pyval_old,   'String'));       zp   = str2double(get(plotinfo.Pzval_old,   'String'));
    else    % else use home position
        rollp = 0;    pitchp = 0;   yawp = 0;     xp = 0;     yp = 0;     zp = 0;
    end
    % --- assume all your scaler‐dependent variables and plotinfo fields are set above ---
    maxDirs   = ceil(180/(1.0*scaler))*ceil(360/(5*scaler));
    maxPoints = maxDirs;      % rough upper bound
    w_x = zeros(1, maxPoints);
    w_y = zeros(1, maxPoints);
    w_z = zeros(1, maxPoints);
    p   = 1;
    tol_r     = 0.0005;       % bisect tolerance
    d_theta = 1.0*scaler * pi/180; % radians
    d_phi = 0.25*scaler * pi/180;

    % precompute a safe initial radius bound from your XYZ limits
    dx = max(abs([x_lower_limit-xp, x_upper_limit-xp]));
    dy = max(abs([y_lower_limit-yp, y_upper_limit-yp]));
    dz = max(abs([z_lower_limit-zp, z_upper_limit-zp]));
    r_init = sqrt(dx^2+dy^2+dz^2);

    N_theta = ceil(pi/d_theta);
    for k = 0:N_theta
        theta = k*d_theta;
        if theta>pi, theta = pi; end
        stheta = sin(theta);  ctheta = cos(theta);
        for phi = 0 : d_phi : 2*pi - d_phi
            nx = stheta*cos(phi);  ny = stheta*sin(phi);  nz = ctheta;
            %–– find bracket [r_lo,r_hi] ––
            r_lo = 0;  r_hi = r_init;
            while true
                xt = xp + r_hi*nx;  yt = yp + r_hi*ny;  zt = zp + r_hi*nz;
                sol = stew_inverse_ws(xsi,ysi,zsi,xmi,ymi,zmi,rollp,pitchp,yawp, ...
                    xt,yt,zt,rpyAxes) - zpdLegLength;
                if any(sol > leg_upper_limit | sol < leg_lower_limit), break; end
                r_lo = r_hi;  r_hi = 2*r_hi;
            end
            %–– bisect to tol_r ––
            while (r_hi - r_lo) > tol_r
                r_mid = 0.5*(r_lo + r_hi);
                xm = xp + r_mid*nx;  ym = yp + r_mid*ny;  zm = zp + r_mid*nz;
                solm = stew_inverse_ws(xsi,ysi,zsi,xmi,ymi,zmi,rollp,pitchp,yawp, ...
                    xm,ym,zm,rpyAxes) - zpdLegLength;
                if any(solm > leg_upper_limit | solm < leg_lower_limit)
                    r_hi = r_mid;
                else
                    r_lo = r_mid;
                end
            end
            %–– record & occasionally report ––
            xf = xp + r_lo*nx;  yf = yp + r_lo*ny;  zf = zp + r_lo*nz;
            p = p + 1;  w_x(p)=xf;  w_y(p)=yf;  w_z(p)=zf;
            if mod(p,500)==0
                tElapsed = toc(tStart);
                str = regexprep(sprintf('%.0f', p), '\d(?=(\d{3})+$)', '$&,');
                update_status(sprintf('... point %s at (X, Y, Z) = (%02.3f, %02.3f, %02.3f)mm  (time: %02d:%05.2f)', ...
                    str, xf, yf, zf, floor(tElapsed/60), rem(tElapsed,60)));
            end
            %–– cancellation check ––
            if isempty(d) || ~all(isvalid(d))
                disp('Computation cancelled by user.');
                set(findall(0,'Tag','workspace_me_btn'),'Enable','on');
                set(findall(0,'Tag','reachable_workspace_me_btn'),'Enable','on');
                return;
            end
        end
    end
    %–– trim off the unused pre‑allocation and compute center plane ––
    w_x = w_x(2:p);  w_y = w_y(2:p);  w_z = w_z(2:p);
    Zc  = 0.5*(max(w_z) + min(w_z));
    %–– find first point that falls below the center plane ––
    firstLower = find(w_z < Zc, 1, 'first');
    if isempty(firstLower)
        upIdx = 1:numel(w_z);
        dnIdx = [];
    else
        upIdx = 1:firstLower-1;
        dnIdx = firstLower:numel(w_z);
    end
    %–– now pull out the correlated x,y,z into your upper and lower arrays ––
    %     rollp = 0;    pitchp = 0;   yawp = 0;     xp = 0;     yp = 0;     zp = 0;
    w_x_u = w_x(upIdx)-xp;  w_y_u = w_y(upIdx)-yp;  w_z_u = w_z(upIdx)-zp;
    w_x_d = w_x(dnIdx)-xp;  w_y_d = w_y(dnIdx)-yp;  w_z_d = w_z(dnIdx)-zp;
    save('reachable_workspace_data_NEW.mat', ...
        'w_x_u','w_y_u','w_z_u','w_x_d','w_y_d','w_z_d','scaler','view_frame','rpy_axes');
end





if isfile('reachable_workspace_data_NEW.mat')
    load('reachable_workspace_data_NEW.mat');
    allPts = [ [w_x_u(:), w_y_u(:), w_z_u(:)]; [w_x_d(:), w_y_d(:), w_z_d(:)] ]; 
    all_x = [w_x_u(:); w_x_d(:)];    all_y = [w_y_u(:); w_y_d(:)];    all_z = [w_z_u(:); w_z_d(:)];
    x_limits = [min(all_x(:)), max(all_x(:))];    y_limits = [min(all_y(:)), max(all_y(:))];    z_limits = [min(all_z(:)), max(all_z(:))];

    % 1) build an alphaShape
    alphaVal = 30;  % tune this: smaller → more concave detail, larger → smoother
    shp = alphaShape(allPts(:,1), allPts(:,2), allPts(:,3), alphaVal);
    [tri, ptsOut] = boundaryFacets(shp);
    
    figure(500); clf; hold on;
    tiledlayout(1,1,'Padding','loose','TileSpacing','loose');    nexttile; hold on;      set(gcf,'Renderer','opengl');
    upDir = dataset_view_frame('reachable_workspace_data_NEW.mat');   upDir = upDir(3,:)';   % colour along the window's up
    h = patch('Vertices',ptsOut,'Faces',tri,'FaceColor','interp',  'FaceVertexCData',ptsOut*upDir,'EdgeColor','none','FaceAlpha',0.6);
    
%     if (homeNewOld == 0)
%     maxArea = scaler;
%     V = ptsOut; F = h.Faces;    v1 = V(F(:,2),:) - V(F(:,1),:);    v2 = V(F(:,3),:) - V(F(:,1),:);    A  = 0.5 * sqrt( sum( cross(v1,v2,2).^2, 2 ) );  % M×1
%     keep = A <= maxArea;    h.Faces = F(keep,:);    drawnow;
%     end
    shading interp;     colormap(turbo);   lighting phong;     material shiny;
    h1 = camlight('headlight');   h2 = camlight('headlight');  h2.Position = -h2.Position;   light('Position',[0 0 10],'Style','infinite','Color',[1 1 1]);     % headlight at camera
    rotate3d on;
   
    totalPts = numel(w_x_u) + numel(w_x_d);
    maxSamples = 6000;                 % desired cap
    if totalPts <= maxSamples;        step = 1;    else;        step = ceil(totalPts/maxSamples);    end
    xu = w_x_u(1:step:end);  yu = w_y_u(1:step:end);  zu = w_z_u(1:step:end);    xd = w_x_d(1:step:end);  yd = w_y_d(1:step:end);  zd = w_z_d(1:step:end);
    scatter3([xu,xd], [yu,yd], [zu,zd], 6, [0.6,0.6,0.6], 'filled', 'MarkerFaceAlpha',0.25);

    % Coordinate axes
    plot3([0 0], [0 0], [0 0.5*max(z_limits(:))], '-^k', 'MarkerSize', 5, 'LineWidth', 5);
    plot3([0 0], [0 0.5*max(y_limits(:))], [0 0], '-<k', 'MarkerSize', 5, 'LineWidth', 5);
    plot3([0 0.5*max(x_limits(:))], [0 0], [0 0], '->k', 'MarkerSize', 5, 'LineWidth', 5);
    axis([1.1*x_limits, 1.1*y_limits, z_limits]);
    grid on;    grid minor;
    xlabel('X [mm]');    ylabel('Y [mm]');    zlabel('Z [mm]');
    set(findall(gcf, '-property', 'FontSize'), 'FontSize', 48);
    annotation('textbox', [0.541354166666665,0.651204188481693,0.45,0.3], ...
        'String', sprintf('X = [%.3f, %.3f] mm\nY = [%.3f, %.3f] mm\nZ = [%.3f, %.3f] mm', ...
        x_limits(1), x_limits(2), y_limits(1), y_limits(2), z_limits(1), z_limits(2)), ...
        'Units', 'normalized', 'FontSize', 38,'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
        'Color', 'black', 'EdgeColor', 'none', 'Interpreter', 'tex');
    set(gca, 'TickLabelInterpreter', 'latex');    set(gcf, 'Color', 'w');
    set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'on');
    set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'on');
    % Final time
    tEnd = toc(tStart);
    % fprintf('...Total elapsed time: %d min and %.3f sec...\n', floor(tEnd/60), rem(tEnd, 60));
    stringMSG = sprintf('Reachable workspace limits:\nX -> [%.3f, %.3f]mm\nY -> [%.3f, %.3f]mm\nZ -> [%.3f, %.3f]mm\n', ...
        x_limits(1), x_limits(2),         y_limits(1), y_limits(2),         z_limits(1), z_limits(2));
    update_status(stringMSG);
    disp(stringMSG)
    stringMSG = sprintf('...Total elapsed time:  %02d:%06.3f ...\n', floor(tEnd/60), rem(tEnd, 60));
    update_status(stringMSG);
    fprintf('...Total elapsed time:  %02d:%06.3f ...\n', floor(tEnd/60), rem(tEnd, 60));
    frame_view(gca, 315, 12.5, dataset_view_frame('reachable_workspace_data_NEW.mat'));
    fig = gcf;
    set(fig, 'Units', 'pixels');
    set(fig, 'Position', [100, 100, 1650, 1000]);  % Fixed size, adjust as needed
else
    stringMSG = '...... "reachable_workspace_data_NEW.mat" not found ......';
    update_status(stringMSG);
    stringMSG = '...... run NEW workspace first or include file ......';
    update_status(stringMSG);
    stringMSG = '...... Computation cancelled by program ......';
    update_status(stringMSG);
    disp('"reachable_workspace_data_NEW.mat" not found')
    disp('Computation cancelled by program - run NEW workspace first or include file.');
    set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'on');
    set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'on');
    msgbox('... "reachable_workspace_data_NEW.mat" not found - exiting early ...', 'File Missing', 'warn');
    return;
end


end


