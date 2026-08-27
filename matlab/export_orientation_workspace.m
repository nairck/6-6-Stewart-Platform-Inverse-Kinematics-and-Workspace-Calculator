function export_orientation_workspace(ANGULAR_STEP_SIZE, newOrRecall)
tStart = tic;
disp('working on orientation workspace export...')
% Build filename based on newOrRecall flag and then test/load in one block:
if newOrRecall
    fname = 'orientation_workspace_data_NEW.mat';
else
    fname = 'orientation_workspace_data_RECALL.mat';
end

if isfile(fname)
    load(fname);
else
    msg = sprintf('... "%s" not found - exiting early ...', fname);
    disp(msg);
    msgbox(msg, 'File Missing', 'warn');
    return;
end


w_x_u = w_roll_u;    w_y_u = w_pitch_u;    w_z_u = w_yaw_u;
w_x_d = w_roll_d;    w_y_d = w_pitch_d;    w_z_d = w_yaw_d;
allPts = [ [w_x_u(:), w_y_u(:), w_z_u(:)]; [w_x_d(:), w_y_d(:), w_z_d(:)] ];
all_x = [w_x_u(:); w_x_d(:)];    all_y = [w_y_u(:); w_y_d(:)];    all_z = [w_z_u(:); w_z_d(:)];
x_limits = [min(all_x(:)), max(all_x(:))];    y_limits = [min(all_y(:)), max(all_y(:))];    z_limits = [min(all_z(:)), max(all_z(:))];

% 1) build an alphaShape
alphaVal = 3;  % tune this: smaller → more concave detail, larger → smoother
shp = alphaShape(allPts(:,1), allPts(:,2), allPts(:,3), alphaVal);
[tri, ptsOut] = boundaryFacets(shp);

figure(601); clf; hold on;
tiledlayout(1,1,'Padding','loose','TileSpacing','loose');    nexttile; hold on;      set(gcf,'Renderer','opengl');
upDir = dataset_view_frame(fname);   upDir = upDir(3,:)';   % colour along the window's up
h = patch('Vertices',ptsOut,'Faces',tri,'FaceColor','interp',  'FaceVertexCData',ptsOut*upDir,'EdgeColor','none','FaceAlpha',0.6);
% maxArea = 30;   % mm², tweak as needed
% V = ptsOut; F = h.Faces;    v1 = V(F(:,2),:) - V(F(:,1),:);    v2 = V(F(:,3),:) - V(F(:,1),:);    A  = 0.5 * sqrt( sum( cross(v1,v2,2).^2, 2 ) );  % M×1
% keep = A <= maxArea;    h.Faces = F(keep,:);    drawnow;
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
set(findall(gcf, '-property', 'FontSize'), 'FontSize', 38);
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
figure(601)

viewD = dataset_view_frame(fname);          % the sketch's "up", stored with the data
frame_view(gca, 335, 12.5, viewD);
fig = gcf;
set(fig, 'Units', 'pixels');
set(fig, 'Position', [100, 100, 1650, 1000]);  % Fixed size, adjust as needed



output_dir = 'Orientation_workspace_output_PNG';
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end
set(gcf, 'WindowState', 'maximized');
ii = 0;

% ANGULAR_STEP_SIZE;
for i = 1:360/ANGULAR_STEP_SIZE:360
    ii = ii + 1;
    figure(601)
    frame_view(gca, 335+i, 12.5, viewD);
    drawnow;
    fig = gcf;
    set(fig, 'Units', 'pixels');
    set(fig, 'Position', [100, 100, 1650, 1000]);  % Fixed size, adjust as needed
    F = getframe(gcf);
    filename = fullfile(output_dir, sprintf('orientation_workspace_%1d.png', ii));
    %         exportgraphics(gcf, filename, 'Resolution', 100);
    imwrite(F.cdata, filename);
end



end