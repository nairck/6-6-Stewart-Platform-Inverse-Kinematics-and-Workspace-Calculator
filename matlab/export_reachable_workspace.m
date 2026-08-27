function export_reachable_workspace(ANGULAR_STEP_SIZE, newOrRecall)
tStart = tic;
disp('working on reachable workspace export...')
% Build filename based on newOrRecall flag and then test/load in one block:
if newOrRecall
    fname = 'reachable_workspace_data_NEW.mat';
else
    fname = 'reachable_workspace_data_RECALL.mat';
end

if isfile(fname)
    load(fname);
else
    msg = sprintf('... "%s" not found - exiting early ...', fname);
    disp(msg);
    msgbox(msg, 'File Missing', 'warn');
    return;
end

allPts = [ [w_x_u(:), w_y_u(:), w_z_u(:)]; [w_x_d(:), w_y_d(:), w_z_d(:)] ];
all_x = [w_x_u(:); w_x_d(:)];    all_y = [w_y_u(:); w_y_d(:)];    all_z = [w_z_u(:); w_z_d(:)];
x_limits = [min(all_x(:)), max(all_x(:))];    y_limits = [min(all_y(:)), max(all_y(:))];    z_limits = [min(all_z(:)), max(all_z(:))];

% 1) build an alphaShape
alphaVal = 50;  % tune this: smaller → more concave detail, larger → smoother
shp = alphaShape(allPts(:,1), allPts(:,2), allPts(:,3), alphaVal);
[tri, ptsOut] = boundaryFacets(shp);

figure(501); clf; hold on;
tiledlayout(1,1,'Padding','loose','TileSpacing','loose');    nexttile; hold on;      set(gcf,'Renderer','opengl');
upDir = dataset_view_frame(fname);   upDir = upDir(3,:)';   % colour along the window's up
h = patch('Vertices',ptsOut,'Faces',tri,'FaceColor','interp',  'FaceVertexCData',ptsOut*upDir,'EdgeColor','none','FaceAlpha',0.6);

maxArea = scaler;
V = ptsOut; F = h.Faces;    v1 = V(F(:,2),:) - V(F(:,1),:);    v2 = V(F(:,3),:) - V(F(:,1),:);    A  = 0.5 * sqrt( sum( cross(v1,v2,2).^2, 2 ) );  % M×1
keep = A <= maxArea;    h.Faces = F(keep,:);    drawnow;
shading interp;     colormap(turbo);   lighting phong;     material shiny;
h1 = camlight('headlight');   h2 = camlight('headlight');  h2.Position = -h2.Position;   light('Position',[0 0 10],'Style','infinite','Color',[1 1 1]);     % headlight at camera
rotate3d on;

totalPts = numel(w_x_u) + numel(w_x_d);
maxSamples = 6000;                 % desired cap
if totalPts <= maxSamples;        step = 1;    else;        step = ceil(totalPts/maxSamples);    end
xu = w_x_u(1:step:end);  yu = w_y_u(1:step:end);  zu = w_z_u(1:step:end);    xd = w_x_d(1:step:end);  yd = w_y_d(1:step:end);  zd = w_z_d(1:step:end);
scatter3([xu,xd], [yu,yd], [zu,zd], 6, [0.6,0.6,0.6], 'filled', 'MarkerFaceAlpha',0.5);

% Coordinate axes
plot3([0 0], [0 0], [0 0.5*max(z_limits(:))], '-^k', 'MarkerSize', 5, 'LineWidth', 5);
plot3([0 0], [0 0.5*max(y_limits(:))], [0 0], '-<k', 'MarkerSize', 5, 'LineWidth', 5);
plot3([0 0.5*max(x_limits(:))], [0 0], [0 0], '->k', 'MarkerSize', 5, 'LineWidth', 5);
axis([1.1*x_limits, 1.1*y_limits, z_limits]);
grid on;    grid minor;
xlabel('X [mm]');    ylabel('Y [mm]');    zlabel('Z [mm]');
set(findall(gcf, '-property', 'FontSize'), 'FontSize', 38);
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
viewD = dataset_view_frame(fname);          % the sketch's "up", stored with the data
frame_view(gca, 315, 12.5, viewD);




% % allPts = [ [w_x_u(:), w_y_u(:), w_z_u(:)]; [w_x_d(:), w_y_d(:), w_z_d(:)] ];
% % all_x = [w_x_u(:); w_x_d(:)];    all_y = [w_y_u(:); w_y_d(:)];    all_z = [w_z_u(:); w_z_d(:)];
% % x_limits = [min(all_x(:)), max(all_x(:))];    y_limits = [min(all_y(:)), max(all_y(:))];    z_limits = [min(all_z(:)), max(all_z(:))];
% % 
% % % 1) build an alphaShape
% % alphaVal = 30;  % tune this: smaller → more concave detail, larger → smoother
% % shp = alphaShape(allPts(:,1), allPts(:,2), allPts(:,3), alphaVal);
% % [tri, ptsOut] = boundaryFacets(shp);
% % 
% % figure(501); clf; hold on;
% % tiledlayout(1,2,'Padding','loose','TileSpacing','loose');    ax1 = nexttile(1); hold on;      set(gcf,'Renderer','opengl');
% % h = patch('Vertices',ptsOut,'Faces',tri,'FaceColor','interp',  'FaceVertexCData',ptsOut(:,3),'EdgeColor','none','FaceAlpha',0.6);
% % 
% % % maxArea = scaler*2;
% % % V = ptsOut; F = h.Faces;    v1 = V(F(:,2),:) - V(F(:,1),:);    v2 = V(F(:,3),:) - V(F(:,1),:);    A  = 0.5 * sqrt( sum( cross(v1,v2,2).^2, 2 ) );  % M×1
% % % keep = A <= maxArea;    h.Faces = F(keep,:);    drawnow;
% % shading interp;     colormap(turbo);   lighting phong;     material shiny;
% % h1 = camlight('headlight');   h2 = camlight('headlight');  h2.Position = -h2.Position;   light('Position',[0 0 10],'Style','infinite','Color',[1 1 1]);     % headlight at camera
% % rotate3d on;
% % 
% % totalPts = numel(w_x_u) + numel(w_x_d);
% % maxSamples = 6000;                 % desired cap
% % if totalPts <= maxSamples;        step = 1;    else;        step = ceil(totalPts/maxSamples);    end
% % xu = w_x_u(1:step:end);  yu = w_y_u(1:step:end);  zu = w_z_u(1:step:end);    xd = w_x_d(1:step:end);  yd = w_y_d(1:step:end);  zd = w_z_d(1:step:end);
% % scatter3([xu,xd], [yu,yd], [zu,zd], 6, [0.6,0.6,0.6], 'filled', 'MarkerFaceAlpha',0.25);
% % 
% % % Coordinate axes
% % plot3([0 0], [0 0], [0 0.5*max(z_limits(:))], '-^k', 'MarkerSize', 5, 'LineWidth', 5);
% % plot3([0 0], [0 0.5*max(y_limits(:))], [0 0], '-<k', 'MarkerSize', 5, 'LineWidth', 5);
% % plot3([0 0.5*max(x_limits(:))], [0 0], [0 0], '->k', 'MarkerSize', 5, 'LineWidth', 5);
% % axis([1.1*x_limits, 1.1*y_limits, z_limits]);
% % grid on;    grid minor;
% % xlabel('X [mm]');    ylabel('Y [mm]');    zlabel('Z [mm]');
% % set(findall(gcf, '-property', 'FontSize'), 'FontSize', 34);
% % annotation('textbox', [0.541354166666665-.48,0.651204188481693,0.45,0.3], ...
% %     'String', sprintf('X = [%.3f, %.3f] mm\nY = [%.3f, %.3f] mm\nZ = [%.3f, %.3f] mm', ...
% %     x_limits(1), x_limits(2), y_limits(1), y_limits(2), z_limits(1), z_limits(2)), ...
% %     'Units', 'normalized', 'FontSize', 25,'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
% %     'Color', 'black', 'EdgeColor', 'none', 'Interpreter', 'tex');
% % set(gca, 'TickLabelInterpreter', 'latex');    set(gcf, 'Color', 'w');
% % set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'on');
% % set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'on');
% % % Final time
% % tEnd = toc(tStart);
% % % fprintf('...Total elapsed time: %d min and %.3f sec...\n', floor(tEnd/60), rem(tEnd, 60));
% % stringMSG = sprintf('Reachable workspace limits:\nX -> [%.3f, %.3f]mm\nY -> [%.3f, %.3f]mm\nZ -> [%.3f, %.3f]mm\n', ...
% %     x_limits(1), x_limits(2),         y_limits(1), y_limits(2),         z_limits(1), z_limits(2));
% % update_status(stringMSG);
% % disp(stringMSG)
% % stringMSG = sprintf('...Total elapsed time:  %02d:%06.3f ...\n', floor(tEnd/60), rem(tEnd, 60));
% % update_status(stringMSG);
% % fprintf('...Total elapsed time:  %02d:%06.3f ...\n', floor(tEnd/60), rem(tEnd, 60));
% % view(ax1, [315, 12.5]);
% % 
% % 
% % 
% % load('orientation_workspace_data_RECALL.mat');
% % w_x_u = w_roll_u;    w_y_u = w_pitch_u;    w_z_u = w_yaw_u;
% % w_x_d = w_roll_d;    w_y_d = w_pitch_d;    w_z_d = w_yaw_d;
% % allPts = [ [w_x_u(:), w_y_u(:), w_z_u(:)]; [w_x_d(:), w_y_d(:), w_z_d(:)] ];
% % all_x = [w_x_u(:); w_x_d(:)];    all_y = [w_y_u(:); w_y_d(:)];    all_z = [w_z_u(:); w_z_d(:)];
% % x_limits = [min(all_x(:)), max(all_x(:))];    y_limits = [min(all_y(:)), max(all_y(:))];    z_limits = [min(all_z(:)), max(all_z(:))];
% % 
% % % 1) build an alphaShape
% % alphaVal = 1;  % tune this: smaller → more concave detail, larger → smoother
% % shp = alphaShape(allPts(:,1), allPts(:,2), allPts(:,3), alphaVal);
% % [tri, ptsOut] = boundaryFacets(shp);
% % 
% % figure(501); ax2 = nexttile(2); hold on;      set(gcf,'Renderer','opengl');
% % h = patch('Vertices',ptsOut,'Faces',tri,'FaceColor','interp',  'FaceVertexCData',ptsOut(:,3),'EdgeColor','none','FaceAlpha',0.6);
% % % maxArea = 30;   % mm², tweak as needed
% % % V = ptsOut; F = h.Faces;    v1 = V(F(:,2),:) - V(F(:,1),:);    v2 = V(F(:,3),:) - V(F(:,1),:);    A  = 0.5 * sqrt( sum( cross(v1,v2,2).^2, 2 ) );  % M×1
% % % keep = A <= maxArea;    h.Faces = F(keep,:);    drawnow;
% % shading interp;     colormap(turbo);   lighting phong;     material shiny;
% % h1 = camlight('headlight');   h2 = camlight('headlight');  h2.Position = -h2.Position;   light('Position',[0 0 0],'Style','infinite','Color',[1 1 1]);     % headlight at camera
% % rotate3d on;
% % 
% %     totalPts = numel(w_x_u) + numel(w_x_d);
% %     maxSamples = 6000;                 % desired cap
% %     if totalPts <= maxSamples;        step = 1;    else;        step = ceil(totalPts/maxSamples);    end
% %     xu = w_x_u(1:step:end);  yu = w_y_u(1:step:end);  zu = w_z_u(1:step:end);    xd = w_x_d(1:step:end);  yd = w_y_d(1:step:end);  zd = w_z_d(1:step:end);
% % scatter3([xu,xd], [yu,yd], [zu,zd], 6, [0.6,0.6,0.6], 'filled', 'MarkerFaceAlpha',0.25);
% % 
% % % Coordinate axes
% % plot3([0 0], [0 0], [0 0.5*max(all_z(:))], '-^k', 'MarkerSize', 5, 'LineWidth', 5);
% % plot3([0 0], [0 0.5*max(all_y(:))], [0 0], '-<k', 'MarkerSize', 5, 'LineWidth', 5);
% % plot3([0 0.25*max(all_x(:))], [0 0], [0 0], '->k', 'MarkerSize', 5, 'LineWidth', 5);
% % axis([1.1*x_limits, 1.1*y_limits, z_limits]);
% % grid on;    grid minor;
% % % set(findall(gcf, '-property', 'FontSize'), 'FontSize', 34);
% % % Display text in the plot
% % annotation('textbox', [0.541354166666665,0.651204188481693,0.45,0.3], ...
% %     'String', sprintf('Roll = [%.3f, %.3f] °\nPitch = [%.3f, %.3f] °\nYaw = [%.3f, %.3f] °', ...
% %     x_limits(1), x_limits(2), y_limits(1), y_limits(2), z_limits(1), z_limits(2)), ...
% %     'Units', 'normalized', ...
% %     'FontSize', 25, ...
% %     'HorizontalAlignment', 'right', ...
% %     'VerticalAlignment', 'top', ...
% %     'Color', 'black', ...
% %     'EdgeColor', 'none', ...
% %     'Interpreter', 'tex');
% % xlabel("Roll [°]", 'FontSize', 34);    ylabel("Pitch [°]", 'FontSize', 34);    zlabel("Yaw [°]", 'FontSize', 34);
% % set(gca, 'TickLabelInterpreter', 'latex', 'FontSize', 34);
% % set(gcf, 'Color', 'w');
% % set(findall(0, 'Tag', 'workspace_me_btn'), 'Enable', 'on');
% % set(findall(0, 'Tag', 'reachable_workspace_me_btn'), 'Enable', 'on');
% % % Final time
% % tEnd = toc(tStart);
% % % fprintf('...Total elapsed time: %d min and %.3f sec...\n', floor(tEnd/60), rem(tEnd, 60));
% % stringMSG = sprintf(['Orientation workspace limits:\nRoll    -> [%1.3f, %1.3f]°\nPitch  -> [%1.3f, %1.3f]°\nYaw   -> [%1.3f, %1.3f]°\n'], ...
% %     x_limits(1), x_limits(2), ...
% %     y_limits(1), y_limits(2), ...
% %     z_limits(1), z_limits(2));
% % update_status(stringMSG);
% % disp(stringMSG)
% % stringMSG = sprintf('...Total elapsed time: %02d:%06.3f ...\n', floor(tEnd/60), rem(tEnd, 60));
% % update_status(stringMSG);
% % fprintf('...Total elapsed time: %02d:%06.3f ...\n', floor(tEnd/60), rem(tEnd, 60));
% % view(ax2,[315, 12.5]);



fig = gcf;
set(fig, 'Units', 'pixels');
set(fig, 'Position', [100, 100, 1650, 1000]);  % Fixed size, adjust as needed
% set(fig, 'Position', [100, 100, 1750, 700]);  % Fixed size, adjust as needed


% output_dir = 'Adjusted_workspace_output_PNG';
output_dir = 'Reachable_workspace_output_PNG';
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
set(gcf, 'WindowState', 'maximized');
ii = 0;
temp = 360/ANGULAR_STEP_SIZE;
for i = 1:temp:360
    ii = ii + 1;
    figure(501);
    frame_view(gca, 315+i-temp, 12.5, viewD);
%     view(ax1, [315+i, 12.5]);
%     view(ax2,[315+i, 12.5]);
    drawnow;
    fig = gcf;
    set(fig, 'Units', 'pixels');
%     set(fig, 'Position', [100, 100, 1750, 700]);  % Fixed size, adjust as needed
    set(fig, 'Position', [100, 100, 1650, 1000]);  % Fixed size, adjust as needed
    F = getframe(gcf);
%     filename = fullfile(output_dir, sprintf('adjusted_workspace_%1d.png', ii));
    filename = fullfile(output_dir, sprintf('reachable_workspace_%1d.png', ii));
    imwrite(F.cdata, filename);
end

end