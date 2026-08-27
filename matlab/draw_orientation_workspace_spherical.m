function draw_orientation_workspace_spherical(scaler, plotinfo, homeNewOld)
tStart = tic;
disp('working on orientation workspace...')
tic
set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'off');
set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'off');
% Get handle to the message dialog
d = findall(0, 'Type', 'figure', 'Name', 'Draw Orientation Workspace Progress');
if isempty(d) || ~all(isvalid(d))
    disp('Computation cancelled by user.');
    set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'on');
    set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'on');
    return;
end
% plotinfo = get(gcf, 'UserData');
if (scaler ~= 100)
    rpyAxes = rpy_axes_of(plotinfo);          % roll/pitch/yaw axes assignment
    % The 3D window keeps the sketch's "up".  The orientation workspace's axes
    % are the roll / pitch / yaw rotation axes, i.e. the sketch's display
    % frame times the assignment's permutation (a rotation vector transforms
    % like a vector); stored with the data (see frame_view.m).
    if isfield(plotinfo, 'sketch_disp'), sketchD = diag([-1 -1 1]) * plotinfo.sketch_disp; else, sketchD = eye(3); end   % unturned sketch frame
    view_frame = sketchD * rpy_perm(rpyAxes);
    rpy_axes = rpyAxes;
    zpdLegLength   = str2double(get(plotinfo.zpdLegLength,'String'));
    leg_lo         = str2double(get(plotinfo.jointmin,   'String'));
    leg_hi         = str2double(get(plotinfo.jointmax,   'String'));
    roll_lo        = str2double(get(plotinfo.rollmin,    'String'));
    roll_hi        = str2double(get(plotinfo.rollmax,    'String'));
    pitch_lo       = str2double(get(plotinfo.pitchmin,   'String'));
    pitch_hi       = str2double(get(plotinfo.pitchmax,   'String'));
    yaw_lo         = str2double(get(plotinfo.yawmin,     'String'));
    yaw_hi         = str2double(get(plotinfo.yawmax,     'String'));
    xsi = cellfun(@(h)str2double(get(h,'String')),{plotinfo.base1x,plotinfo.base2x,plotinfo.base3x,plotinfo.base4x,plotinfo.base5x,plotinfo.base6x});
    ysi = cellfun(@(h)str2double(get(h,'String')),{plotinfo.base1y,plotinfo.base2y,plotinfo.base3y,plotinfo.base4y,plotinfo.base5y,plotinfo.base6y});
    zsi = cellfun(@(h)str2double(get(h,'String')),{plotinfo.base1z,plotinfo.base2z,plotinfo.base3z,plotinfo.base4z,plotinfo.base5z,plotinfo.base6z});
    xmi = cellfun(@(h)str2double(get(h,'String')),{plotinfo.plat1x, plotinfo.plat2x, plotinfo.plat3x, plotinfo.plat4x, plotinfo.plat5x, plotinfo.plat6x});
    ymi = cellfun(@(h)str2double(get(h,'String')),{plotinfo.plat1y, plotinfo.plat2y, plotinfo.plat3y, plotinfo.plat4y, plotinfo.plat5y, plotinfo.plat6y});
    zmi = cellfun(@(h)str2double(get(h,'String')),{plotinfo.plat1z, plotinfo.plat2z, plotinfo.plat3z, plotinfo.plat4z, plotinfo.plat5z, plotinfo.plat6z});
    %— choose pose (home/new/old) —
    if homeNewOld==1         % new
        roll0  = str2double(get(plotinfo.roll,    'String'));
        pitch0 = str2double(get(plotinfo.pitch,   'String'));
        yaw0   = str2double(get(plotinfo.yaw,     'String'));
        x0     = str2double(get(plotinfo.Pxval,   'String'));
        y0     = str2double(get(plotinfo.Pyval,   'String'));
        z0     = str2double(get(plotinfo.Pzval,   'String'));
    elseif homeNewOld==2     % old
        roll0  = str2double(get(plotinfo.roll_old, 'String'));
        pitch0 = str2double(get(plotinfo.pitch_old,'String'));
        yaw0   = str2double(get(plotinfo.yaw_old,  'String'));
        x0     = str2double(get(plotinfo.Pxval_old,'String'));
        y0     = str2double(get(plotinfo.Pyval_old,'String'));
        z0     = str2double(get(plotinfo.Pzval_old,'String'));
    else                     % home
        roll0=0; pitch0=0; yaw0=0; x0=0; y0=0; z0=0;
    end

    %— radial‐bisection parameters —
    tol_r   = 0.0005;
    d_theta = 1.0*scaler * pi/180;
    d_phi   = 0.25*scaler * pi/180;
    % safe initial radius in angle‐space
    r_init  = max([roll_hi-roll0, roll0-roll_lo, pitch_hi-pitch0, pitch0-pitch_lo, yaw_hi-yaw0, yaw0-yaw_lo]);

    Ntheta = ceil(pi/d_theta);
    maxPts = Ntheta * ceil(2*pi/d_phi);
    w_roll = zeros(1,maxPts);
    w_pitch= zeros(1,maxPts);
    w_yaw  = zeros(1,maxPts);
    p = 1;

    %— spherical sweep in (Δroll,Δpitch,Δyaw) —
    for k=0:Ntheta
        theta = min(k*d_theta,pi);
        st = sin(theta); ct = cos(theta);
        for phi=0:d_phi:2*pi-d_phi
            nx = st*cos(phi); ny = st*sin(phi); nz = ct;
            %— bracket r_lo,r_hi —
            r_lo=0; r_hi=r_init;
            while true
                rr = r_hi*[nx,ny,nz] + [roll0,pitch0,yaw0];
                sol = stew_inverse_ws(xsi,ysi,zsi,xmi,ymi,zmi, rr(1),rr(2),rr(3), x0,y0,z0, rpyAxes) - zpdLegLength;
                if any(sol>leg_hi | sol<leg_lo), break; end
                r_lo=r_hi; r_hi=2*r_hi;
            end
            %— bisection down to tol_r —
            while r_hi-r_lo>tol_r
                rm = 0.5*(r_lo+r_hi);
                rr = rm*[nx,ny,nz] + [roll0,pitch0,yaw0];
                sol = stew_inverse_ws(xsi,ysi,zsi,xmi,ymi,zmi, rr(1),rr(2),rr(3), x0,y0,z0, rpyAxes) - zpdLegLength;
                if any(sol>leg_hi | sol<leg_lo), r_hi=rm; else r_lo=rm; end
            end
            %— record boundary orientation —
            pr = r_lo*[nx,ny,nz] + [roll0,pitch0,yaw0];
            p = p+1;
            w_roll(p)  = pr(1);
            w_pitch(p) = pr(2);
            w_yaw(p)   = pr(3);
            if mod(p,500)==0
                tE = toc(tStart);
                str = regexprep(sprintf('%.0f', p), '\d(?=(\d{3})+$)', '$&,');
                update_status(sprintf('... point %s at (R, P, Y) = (%.3f, %.3f, %.3f)°  (time: %02d:%05.2f)', ...
                    str, pr(1),pr(2),pr(3), floor(tE/60), rem(tE,60)));
            end
            if isempty(d)||~all(isvalid(d))
                disp('Computation cancelled by user.');
                set(findall(0,'Tag','workspace_me_btn'),'Enable','on');
                set(findall(0,'Tag','reachable_workspace_me_btn'),'Enable','on');
                return;
            end
        end
    end

    %— trim off prealloc, drop index 1 dummy —
    w_roll  = w_roll(2:p);
    w_pitch = w_pitch(2:p);
    w_yaw   = w_yaw(2:p);

    %— split into “upper” (Δyaw>0) vs “lower” (Δyaw<0) —
    dy = w_yaw - yaw0;
    firstLower = find(dy<0,1,'first');
    if isempty(firstLower)
        upIdx = 1:numel(dy); dnIdx=[];
    else
        upIdx = 1:firstLower-1;
        dnIdx= firstLower:numel(dy);
    end

    %     rollp = 0;    pitchp = 0;   yawp = 0;     xp = 0;     yp = 0;     zp = 0;
    w_roll_u  = w_roll(upIdx)-roll0;    w_pitch_u = w_pitch(upIdx)-pitch0;    w_yaw_u   = w_yaw(upIdx)-yaw0;
    w_roll_d  = w_roll(dnIdx)-roll0;    w_pitch_d = w_pitch(dnIdx)-pitch0;    w_yaw_d   = w_yaw(dnIdx)-yaw0;

    save('orientation_workspace_data_NEW.mat', ...
        'w_roll_u','w_pitch_u','w_yaw_u', ...
        'w_roll_d','w_pitch_d','w_yaw_d','scaler','view_frame','rpy_axes');
end

if isfile('orientation_workspace_data_NEW.mat')
    load('orientation_workspace_data_NEW.mat');
    w_x_u = w_roll_u;    w_y_u = w_pitch_u;    w_z_u = w_yaw_u;
    w_x_d = w_roll_d;    w_y_d = w_pitch_d;    w_z_d = w_yaw_d;
    allPts = [ [w_x_u(:), w_y_u(:), w_z_u(:)]; [w_x_d(:), w_y_d(:), w_z_d(:)] ]; 
    all_x = [w_x_u(:); w_x_d(:)];    all_y = [w_y_u(:); w_y_d(:)];    all_z = [w_z_u(:); w_z_d(:)];
    x_limits = [min(all_x(:)), max(all_x(:))];    y_limits = [min(all_y(:)), max(all_y(:))];    z_limits = [min(all_z(:)), max(all_z(:))];

    % 1) build an alphaShape
    alphaVal = 3;  % tune this: smaller → more concave detail, larger → smoother
    shp = alphaShape(allPts(:,1), allPts(:,2), allPts(:,3), alphaVal);
    [tri, ptsOut] = boundaryFacets(shp);
    
    figure(600); clf; hold on;
    tiledlayout(1,1,'Padding','loose','TileSpacing','loose');    nexttile; hold on;      set(gcf,'Renderer','opengl');
    upDir = dataset_view_frame('orientation_workspace_data_NEW.mat');   upDir = upDir(3,:)';   % colour along the window's up
    h = patch('Vertices',ptsOut,'Faces',tri,'FaceColor','interp',  'FaceVertexCData',ptsOut*upDir,'EdgeColor','none','FaceAlpha',0.6);
    
    %     maxArea = 30;   % mm², tweak as needed
    %     V = ptsOut; F = h.Faces;    v1 = V(F(:,2),:) - V(F(:,1),:);    v2 = V(F(:,3),:) - V(F(:,1),:);    A  = 0.5 * sqrt( sum( cross(v1,v2,2).^2, 2 ) );  % M×1
    %     keep = A <= maxArea;    h.Faces = F(keep,:);    drawnow;
    shading interp;     colormap(turbo);   lighting phong;     material shiny;
    h1 = camlight('headlight');   h2 = camlight('headlight');  h2.Position = -h2.Position;   light('Position',[0 0 0],'Style','infinite','Color',[1 1 1]);     % headlight at camera
    rotate3d on;
    
    totalPts = numel(w_x_u) + numel(w_x_d);
    maxSamples = 6000;                 % desired cap
    if totalPts <= maxSamples;        step = 1;    else;        step = ceil(totalPts/maxSamples);    end
    xu = w_x_u(1:step:end);  yu = w_y_u(1:step:end);  zu = w_z_u(1:step:end);    xd = w_x_d(1:step:end);  yd = w_y_d(1:step:end);  zd = w_z_d(1:step:end);
    scatter3([xu,xd], [yu,yd], [zu,zd], 6, [0.6,0.6,0.6], 'filled', 'MarkerFaceAlpha',0.25);

    % Coordinate axes
    plot3([0 0], [0 0], [0 0.5*max(all_z(:))], '-^k', 'MarkerSize', 5, 'LineWidth', 5);
    plot3([0 0], [0 0.5*max(all_y(:))], [0 0], '-<k', 'MarkerSize', 5, 'LineWidth', 5);
    plot3([0 0.25*max(all_x(:))], [0 0], [0 0], '->k', 'MarkerSize', 5, 'LineWidth', 5);
    axis([1.1*x_limits, 1.1*y_limits, z_limits]);
    grid on;    grid minor;
    set(findall(gcf, '-property', 'FontSize'), 'FontSize', 48);
    % Display text in the plot
    annotation('textbox', [0.541354166666665,0.651204188481693,0.45,0.3], ...
        'String', sprintf('Roll = [%.3f, %.3f] °\nPitch = [%.3f, %.3f] °\nYaw = [%.3f, %.3f] °', ...
        x_limits(1), x_limits(2), y_limits(1), y_limits(2), z_limits(1), z_limits(2)), ...
        'Units', 'normalized', ...
        'FontSize', 38, ...
        'HorizontalAlignment', 'right', ...
        'VerticalAlignment', 'top', ...
        'Color', 'black', ...
        'EdgeColor', 'none', ...
        'Interpreter', 'tex');
    xlabel("Roll [°]");    ylabel("Pitch [°]");    zlabel("Yaw [°]");
    set(gca, 'TickLabelInterpreter', 'latex');
    set(gcf, 'Color', 'w');
    set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'on');
    set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'on');
    % Final time
    tEnd = toc(tStart);
    % fprintf('...Total elapsed time: %d min and %.3f sec...\n', floor(tEnd/60), rem(tEnd, 60));
    stringMSG = sprintf(['Orientation workspace limits:\nRoll    -> [%1.3f, %1.3f]°\nPitch  -> [%1.3f, %1.3f]°\nYaw   -> [%1.3f, %1.3f]°\n'], ...
        x_limits(1), x_limits(2), ...
        y_limits(1), y_limits(2), ...
        z_limits(1), z_limits(2));
    update_status(stringMSG);
    disp(stringMSG)
    stringMSG = sprintf('...Total elapsed time: %02d:%06.3f ...\n', floor(tEnd/60), rem(tEnd, 60));
    update_status(stringMSG);
    fprintf('...Total elapsed time: %02d:%06.3f ...\n', floor(tEnd/60), rem(tEnd, 60));
        figure(600)
    frame_view(gca, 335, 12.5, dataset_view_frame('orientation_workspace_data_NEW.mat'));
    fig = gcf;
    set(fig, 'Units', 'pixels');
    set(fig, 'Position', [100, 100, 1650, 1000]);  % Fixed size, adjust as needed
else
    stringMSG = '...... "orientation_workspace_data_NEW.mat" not found ......';
    update_status(stringMSG);
    stringMSG = '...... run NEW workspace first or include file ......';
    update_status(stringMSG);
    stringMSG = '...... Computation cancelled by program ......';
    update_status(stringMSG);
    disp('"orientation_workspace_data_NEW.mat" not found')
    disp('Computation cancelled by program - run NEW workspace first or include file.');
    set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'on');
    set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'on');
    msgbox('... "orientation_workspace_data_NEW.mat" not found - exiting early ...', 'File Missing', 'warn');
    return;

end
end



