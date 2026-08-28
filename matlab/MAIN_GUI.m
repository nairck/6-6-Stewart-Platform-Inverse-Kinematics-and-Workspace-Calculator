function MAIN_GUI(fcn)
% MAIN_GUI Hexapod Calculator
%
% fcn: 'stew' to build GUI, other strings to handle callbacks.

if nargin<1, fcn = 'stew'; end

titleStr = 'Hexapod Inverse Kinematics and Workspace Solver';

switch fcn
    case 'stew'
        myname = mfilename;
        % Window: the original 720 x 710 figure, 150 px wider for the Z column
        % in each joint table and 50 px shorter for the removed plane-height
        % rows.  RS/TS are the resulting shifts of the right-hand block and of
        % everything above the ZPD Leg Length row (identical to config.py).
        RS = 150;  TS = -50;
        fig = figure( ...
            'Position',centerfig(720+RS,710+TS), ...
            'Resize','off','MenuBar','none','NumberTitle','off', ...
            'Name',titleStr,'Interruptible','off', ...
            'Color',get(0,'DefaultUIControlBackgroundColor'), ...
            'CloseRequestFcn',sprintf('%s(''quit'');',myname), ...
            'KeyPressFcn',@(src,evt) escape_to_quit(evt,myname));
        % Sketch drawing region: from just inside the "(turns + rem. ang.)"
        % column to the right block's right edge (854), from above the "Colour
        % Theme" label (58) to below the Leg Actuator Lead row (343).  It sits
        % behind every uicontrol; the drawing is centred in it by 'axis equal'.
        plotinfo.ax = axes('Units','pixels','Position',[376 58 478 285],'Visible','off');
        plotinfo.myname = myname;
        set(fig,'UserData',plotinfo);

        % Headers & axis labels
        uicontrol(fig,'Style','text','String','Zero-Displacement Configuration  [mm]', ...
            'Position',[-6,685+TS,250,18],'FontWeight','bold','FontSize',8,'ForegroundColor','#00008b');
        uicontrol(fig,'Style','text','String','Workspace Search Limits and Constraints', ...
            'Position',[465+RS,630+TS,250,18],'FontWeight','bold','FontSize',8,'ForegroundColor','#00008b');
        % column headers + adjust buttons: base x/y/z at 55/130/205, platform
        % x/y/z at 360/434/509 (a 75 px Z column added to each table).
        colHdr = {'xsi',80; 'ysi',155; 'zsi',230; 'xmi',387; 'ymi',457; 'zmi',532};
        for i=1:size(colHdr,1)
            uicontrol(fig,'Style','text','String',colHdr{i,1},'Position',[colHdr{i,2},585,20,12]);
        end
        adjBtn = {'xsi',102; 'ysi',177; 'zsi',252; 'xmi',409; 'ymi',479; 'zmi',554};
        for i=1:size(adjBtn,1)
            uicontrol(fig,'Style','pushbutton','String','±','Position',[adjBtn{i,2} 581 20 17], ...
                'Callback',@(s,e)openAdjustDlg(adjBtn{i,1}));
        end

        % Zero-Displacement: only the ZPD leg length remains on the row under the
        % header (every joint now carries its own Z in the tables below).
        uicontrol(fig,'Style','text','String','ZPD Leg Length:','Position',[24,612,120,13]);
        plotinfo.zpdLegLength = uicontrol(fig,'Style','edit','String','0', ...
            'Position',[128,607,70,20],'BackgroundColor','w', ...
            'Callback',sprintf('%s(''base'');',myname));

        % Base coordinates 1–6 (X, Y, Z)
        for i=1:6
            yT = 567-(i-1)*25; yE = yT-7;
            uicontrol(fig,'Style','text','String',sprintf('Base %d:',i),'Position',[5,yT,50,12]);
            plotinfo.(sprintf('base%dx',i)) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[55,yE,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''base'');',myname));
            plotinfo.(sprintf('base%dy',i)) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[130,yE,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''base'');',myname));
            plotinfo.(sprintf('base%dz',i)) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[205,yE,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''base'');',myname));
        end

        % Platform coordinates 1–6 (X, Y, Z)
        for i=1:6
            yT = 567-(i-1)*25; yE = yT-7;
            uicontrol(fig,'Style','text','String',sprintf('Platform %d:',i),'Position',[300,yT,60,12]);
            plotinfo.(sprintf('plat%dx',i)) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[360,yE,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''plat'');',myname));
            plotinfo.(sprintf('plat%dy',i)) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[434,yE,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''plat'');',myname));
            plotinfo.(sprintf('plat%dz',i)) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[509,yE,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''plat'');',myname));
        end

        % Constraints header & labels
        uicontrol(fig,'Style','text','String','Constraints','Position',[455+RS,579+TS,130,18], ...
            'FontWeight','bold','FontSize',8,'ForegroundColor','#A2142F');
        uicontrol(fig,'Style','text','String','min','Position',[585+RS,585+TS,20,12]);
        uicontrol(fig,'Style','text','String','max','Position',[655+RS,585+TS,25,12]);

        % Roll/Pitch/Yaw constraints
        C = {
            'Roll [° about x]:','roll',563,560;
            'Pitch [° about y]:','pitch',543,538;
            'Yaw [° about z]:','yaw',521,516;
            };
        lblNames = {'lbl_roll', 'lbl_pitch', 'lbl_yaw'};
        for k=1:3
            plotinfo.(lblNames{k}) = uicontrol(fig,'Style','text','String',C{k,1},'Position',[475+RS,C{k,3}+TS,85,13]);
            plotinfo.([C{k,2},'min']) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[560+RS,C{k,4}+TS,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''constraints'');',myname));
            plotinfo.([C{k,2},'max']) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[634+RS,C{k,4}+TS,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''constraints'');',myname));
        end

        % X/Y/Z constraints
        D = {
            'X [mm]:','px',499,494;
            'Y [mm]:','py',478,472;
            'Z [mm]:','pz',455,450;
            };
        for k=1:3
            uicontrol(fig,'Style','text','String',D{k,1},'Position',[495+RS,D{k,3}+TS,50,13]);
            plotinfo.([D{k,2},'min']) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[560+RS,D{k,4}+TS,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''constraints'');',myname));
            plotinfo.([D{k,2},'max']) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[634+RS,D{k,4}+TS,70,20],'BackgroundColor','w', ...
                'Callback',sprintf('%s(''constraints'');',myname));
        end

        % Leg‑length constraint
        uicontrol(fig,'Style','text','String','Leg Length [mm]:','Position',[467+RS,433+TS,100,13]);
        plotinfo.jointmin = uicontrol(fig,'Style','edit','String','0','Position',[560+RS,428+TS,70,20], ...
            'BackgroundColor','w','Callback',sprintf('%s(''misc'');',myname));
        plotinfo.jointmax = uicontrol(fig,'Style','edit','String','0','Position',[634+RS,428+TS,70,20], ...
            'BackgroundColor','w','Callback',sprintf('%s(''misc'');',myname));

        % Leg Actuator Lead row
        uicontrol(fig,'Style','text','String','Leg Actuator Lead [mm/rev]:', ...
            'Position',[476+RS,412+TS,150,13]);
        plotinfo.actuatorLead = uicontrol(fig,'Style','edit','String','0', ...
            'Position',[634+RS,406+TS,70,20], ...
            'BackgroundColor',[1,1,0.9], ...
            'Callback',sprintf('%s(''misc'');',myname));

        % Prismatic leg outputs header & columns
        uicontrol(fig,'Style','text','String','OUTPUTS - Leg Lengths in [mm] and Angular Adjustment in [°]:', ...
            'Position',[0,399,415,22],'FontWeight','bold','FontSize',10,'ForegroundColor','#00008b');
        hdr = {
            'abs. old',[60,385,50,15];
            'abs. new',[123,385,50,15];
            'abs. delta',[184,385,50,15];
            'rel. delta',[246,385,50,15];
            'ang. delta [°]',[298,385,70,15];
            };
        for i=1:size(hdr,1)
            uicontrol(fig,'Style','text','String',hdr{i,1},'Position',hdr{i,2});
        end
        legY = [365 340 315 290 265 240];
        legC = {'#0072BD','#D95319','#EDB120','#7E2F8E','#77AC30','#4DBEEE'};
        for j=1:6
            y = legY(j);
            uicontrol(fig,'Style','text','String',sprintf('Leg %d:',j), ...
                'Position',[5,y+3,50,15],'FontWeight','bold','FontSize',9,'ForegroundColor',legC{j});
            plotinfo.(sprintf('leg%d_old',j))   = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[55,y,60,20],'BackgroundColor','w','Enable','off', ...
                'Callback',sprintf('%s(''legs'');',myname));
            plotinfo.(sprintf('leg%d',j))       = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[117,y,60,20],'BackgroundColor',[.8,1,1],'Enable','inactive', ...
                'Callback',sprintf('%s(''legs'');',myname));
            plotinfo.(sprintf('leg%dabsdelta',j)) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[179,y,60,20],'BackgroundColor',[.8,1,1],'Enable','inactive');
            plotinfo.(sprintf('leg%ddelta',j))    = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[241,y,60,20],'BackgroundColor',[.8,1,1],'Enable','inactive');
            plotinfo.(sprintf('leg%drevrem',j)) = uicontrol(fig, 'Style','text', ...
                'String','(0 rev and 0.0°)', ...
                'Position',[358,y-2,120,20], ...
                'BackgroundColor', get(fig,'Color'), ...
                'ForegroundColor','k', ...
                'HorizontalAlignment','center');
            plotinfo.(sprintf('leg%dangledelta',j)) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[303,y,60,20],'BackgroundColor',[1,1,.9],'Enable','inactive');
        end

        % header for "Rev + Rem Angle” ———
        uicontrol(fig, 'Style','text', ...
            'String','(turns + rem. ang.)', ...
            'Position',[372,385,100,15], ...
            'FontSize',8, ...
            'ForegroundColor','k', ...
            'HorizontalAlignment','left');


        % Input-focus posture header & columns
        uicontrol(fig,'Style','text','String','INPUTS - Change to New Pose:', ...
            'Position',[-4,211-5,270,20],'FontWeight','bold','FontSize',10,'ForegroundColor','#00008b');
        uicontrol(fig,'Style','text','String','abs. old','Position',[60,190,50,15]);
        uicontrol(fig,'Style','text','String','abs. new','Position',[123,190,50,15]);
        uicontrol(fig,'Style','text','String','rel. delta','Position',[184,190,50,15]);
        P = {
            'Roll [°]:','roll',175,170;
            'Pitch [°]:','pitch',150,145;
            'Yaw [°]:','yaw',125,120;
            'X [mm]:','Pxval',100,95;
            'Y [mm]:','Pyval',75,70;
            'Z [mm]:','Pzval',50,45;
            };
        for k=1:size(P,1)
            uicontrol(fig,'Style','text','String',P{k,1},'Position',[5,P{k,3},50,13]);
            plotinfo.(sprintf('%s_old',P{k,2})) = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[55,P{k,4},60,20],'BackgroundColor','w','Enable','off', ...
                'Callback',sprintf('%s(''tablepos'');',myname));
            plotinfo.(P{k,2})                   = uicontrol(fig,'Style','edit','String','0', ...
                'Position',[117,P{k,4},60,20],'BackgroundColor',[.8,1,1],'Enable','off', ...
                'Callback',sprintf('%s(''tablepos'');',myname));
            plotinfo.(sprintf('%sdelta',P{k,2}))= uicontrol(fig,'Style','edit','String','0', ...
                'Position',[179,P{k,4},60,20],'Enable','on');
        end



        % Control buttons & toggles
        btns = {
            'quit','Quit',[768,10,90,25];
            'reset_view_me','Reset View',[676,10,90,25];
            'adj_table_me','Incremental Adj. Table',[530,10,130,25];
            'save_me','Save Everything',[247,10,112,25];
            'overwrite_me','Update Old Pose',[247,37,112,25];
            'zero_me','Zero Input Values',[247,64,112,25];
            'home_me','Go Home Input Val.',[247,91,112,25];
            'solve_inv','Solve Inverse Kinematics',[54,10,186,25];
            'workspace_me','Draw Orientation Workspace',[475+RS,655+TS,150,25];
            'reachable_workspace_me','Draw Reachable Workspace',[475+RS,680+TS,150,25];
            'draw_workspace_me','Export to PNG',[630+RS,655+TS,75,25];
            'draw_reachable_workspace_me','Export to PNG',[630+RS,680+TS,75,25];
            };
        for i=1:size(btns,1)
            plotinfo.(btns{i,1}) = uicontrol(fig,'Style','pushbutton', ...
                'Position',btns{i,3},'String',btns{i,2}, ...
                'Callback',sprintf('%s(''%s'');',myname,btns{i,1}));
        end
        plotinfo.prevsol = uicontrol(fig,'Style','pushbutton','String','<<','Position',[450,50,25,20], ...
            'Visible','off','Callback',sprintf('%s(''prevsol'');',myname));
        plotinfo.solutions_text = uicontrol(fig,'Style','text','String',' ','Position',[482,50,70,15],'Visible','off');
        plotinfo.nextsol = uicontrol(fig,'Style','pushbutton','String','>>','Position',[560,50,25,20], ...
            'Visible','off','Callback',sprintf('%s(''nextsol'');',myname));
        % Double height (two 25 px rows): spans the header row and the ZPD Leg
        % Length row, level with the two Draw-Workspace buttons (605..655); left
        % edge one character in from the "zsi" column header (239), right edge
        % on the platform Z column (509 + 70 = 579).
        plotinfo.editzpd_but = uicontrol(fig,'Style','togglebutton','String','Edit Zero-Displacement Coordinates', ...
            'Position',[239,605,340,50],'FontSize',11,'Callback',sprintf('%s(''editzpd'');',myname));
        plotinfo.editConstraints_but = uicontrol(fig,'Style','togglebutton','String','Edit Workspace Search Limits and Constraints', ...
            'Position',[475+RS,604+TS,230,25],'Callback',sprintf('%s(''editConstraints'');',myname));

        % "Current Origin: <name>" - same width as the pose buttons, twice their
        % height (two 25 px buttons + the 2 px gap), top edge level with the
        % INPUTS header (its top is 206 + 20 = 226).  Opens origin_dialog.
        % the label (two or three centred lines) is set by refresh_origin_ui,
        % which load_data calls once the origins are known
        plotinfo.origin_but = uicontrol(fig,'Style','pushbutton', ...
            'String','Current Origin:','Position',[247,174,112,52], ...
            'TooltipString','Choose / add / edit the origin (point of interest) that the pose and workspaces are referenced to', ...
            'Callback',sprintf('%s(''origin_me'');',myname));
        % Origins / points of interest.  Every displayed coordinate and pose is
        % expressed in the frame of the ACTIVE origin; Origin 1 is the reference
        % frame the joints were entered in (offset fixed at zero).
        plotinfo.origins = struct('name',{'Origin 1'},'dx',{0},'dy',{0},'dz',{0},'roll',{0},'pitch',{0},'yaw',{0});
        plotinfo.origin_active = 1;
        plotinfo.rpy_axes = 'XYZ';           % which axis roll / pitch / yaw rotate about
        plotinfo.animate = true;             % animate a solved move (no on-screen control)
        plotinfo.adj_config = adj_config_default(1);   % Incremental Adj. Table set-up
        plotinfo.adj_view = struct('decimals', 3, 'roundUp', 0.99, 'fromHome', true);  % its view settings, session only
        % Sketch display frame (see draw_plat.m): identity until the axes are
        % relabelled with "Change Coords.".
        plotinfo.sketch_disp = eye(3);
        plotinfo.sketch_auto = true;         % choose the standard view from the geometry on the first draw
        % "Change Coords." - single height, directly below the origin button
        % (174..226) at the 2 px pitch of the button stacks.  Opens the modal
        % right-handed axis relabelling dialog.
        plotinfo.coords_but = uicontrol(fig,'Style','pushbutton', ...
            'String','Change Coords.','Position',[247,147,112,25], ...
            'TooltipString','Relabel the X, Y, Z axes (right-handed) and remap every joint, pose, limit and origin accordingly', ...
            'Callback',sprintf('%s(''coords_me'');',myname));

        set(fig,'UserData',plotinfo);

        %----------------------Load data & draw initial platform
        load_data();
        if ~isvalid(fig), return; end       % the user chose Quit in load_data
        plotinfo = get(fig,'UserData');
        gv = @(f) str2double(get(plotinfo.(f),'String'));
        initial_coords = zeros(1,18);
        for i = 1:6
            initial_coords(3*i-2:3*i) = [gv(sprintf('plat%dx',i)), gv(sprintf('plat%dy',i)), ...
                                         gv(sprintf('plat%dz',i)) - gv('Pzval')];
        end
        view(plotinfo.ax, [-30,20]);      % default view first: draw_plat fits the drawing to it
        draw_plat(initial_coords);
        edit_zpd();
        edit_Constraints();
        solve_inverse();
        color_input_box();
        % Remember the start-up state: Quit / Escape / the close button close
        % straight away while nothing has changed since (or since the last save).
        plotinfo = get(fig,'UserData');
        plotinfo.saved_signature = state_signature(fig);
        set(fig,'UserData',plotinfo);

    case 'solve_inv'
        pi = get(gcf,'UserData');
        set(pi.solve_inv,'String','Working...');
        set(pi.prevsol,'Visible','off');
        set(pi.nextsol,'Visible','off');
        set(pi.solutions_text,'Visible','off');
        solve_inverse();
        color_input_box();
        set(pi.solve_inv,'String','Solve Inverse Kinematics');

    case 'prevsol'
        % prev_solution(); color_input_box();

    case 'nextsol'
        % next_solution(); color_input_box();

    case {'base','plat','legs','constraints','tablepos','misc'}
        % A numeric box was edited (typed or pasted; the edit boxes take the
        % standard Ctrl+C / Ctrl+V): normalise it to three decimals.
        normalise_numeric_box(gcbo);

    case 'editzpd'
        edit_zpd();

    case 'editConstraints'
        edit_Constraints();

    case 'origin_me'
        origin_dialog(gcf);

    case 'coords_me'
        change_coords_dialog(gcf);

    case 'adj_table_me'
        incremental_adj_table(gcf);

    case 'reset_view_me'
        % back to the sketch's default view angle and fit (as in the Python
        % version's Reset View); the display frame is kept
        reset_sketch_view(gcf);          % also what a double-click does

    case 'workspace_me'
        pi = get(gcf,'UserData');
        d  = dialog('Position',[500 500 500 180],'Name','Draw Orientation Workspace Progress','WindowStyle','normal'); movegui(d,'center');
        uicontrol(d,'Style','text','Position',[25 145 450 20],'String','Select search resolution and starting pose or recall old solution:','FontSize',9);
        labels = {'High (~10min)','Medium (~1min)','Low (~5sec)','Recall'};
        vals = [0.55,1.2,4,100];
        totalW = numel(labels)*110 + (numel(labels)-1)*10; startX = (500 - totalW)/2;
        for i = 1:numel(labels)
            posX = startX + (i-1)*(110+10);
            uicontrol(d,'Style','pushbutton','Position',[posX 110-5 110 30],'String',labels{i},'FontSize',9, ...
                'Callback',@(~,~)handle_scaler_selection(vals(i),d,pi,get(findobj(d,'Style','radiobutton','Value',1),'UserData')));
        end
        rlbl = {'home','new pose','old pose'};
        n = numel(rlbl);        rw = 100; rg = 20;        tw = n*rw + (n-1)*rg;        sxr = (490 - tw)/2;        ry = (110 + 70)/2 - 10;  % center between 110 and textbox top (70)
        for i = 1:n
            uicontrol(d,'Style','radiobutton','Position',[sxr+(i-1)*(rw+rg)+10 ry rw 20],...
                'String',rlbl{i},'FontSize',9,'Value',i==1,'UserData',i-1,...
                'Callback','set(findobj(gcbf,''Style'',''radiobutton''),''Value'',0);set(gcbo,''Value'',1)');
        end
        message_box = uicontrol(d,'Style','edit','Position',[20 40 460 30],'Max',4,'Enable','inactive', ...
            'HorizontalAlignment','left','BackgroundColor','white','FontSize',9,'String',{'Select a resolution and pose...'});
        setappdata(0,'workspace_message_box',message_box);

        uicontrol(d,'Style','pushbutton','String','Cancel','Position',[190 10 120 25],'Callback',@(~,~)delete(d));

    case 'reachable_workspace_me'
        pi = get(gcf,'UserData');
        d  = dialog('Position',[500 500 500 180],'Name','Draw Reachable Workspace Progress','WindowStyle','normal');
        movegui(d,'center');
        uicontrol(d,'Style','text','Position',[25 145 450 20],'String','Select search resolution and starting pose or recall old solution:','FontSize',9);
        labels = {'High (~10min)','Medium (~1min)','Low (~5sec)','Recall'};
        vals   = [0.55,1.2,4,100]; %0.55
        totalW = numel(labels)*110 + (numel(labels)-1)*10;        sx     = (500 - totalW)/2;
        for i = 1:numel(labels)
            uicontrol(d,'Style','pushbutton','Position',[sx+(i-1)*(110+10) 110-5 110 30],'String',labels{i},'FontSize',9,...
                'Callback',@(~,~)handle_reachable_scaler_selection(vals(i),d,pi,get(findobj(d,'Style','radiobutton','Value',1),'UserData')));
        end
        rlbl   = {'home','new pose','old pose'};
        n = numel(rlbl);        rw = 100; rg = 20;        tw = n*rw + (n-1)*rg;        sxr = (490 - tw)/2;        ry = (110 + 70)/2 - 10;  % center between 110 and textbox top (70)
        for i = 1:n
            uicontrol(d,'Style','radiobutton','Position',[sxr+(i-1)*(rw+rg)+10 ry rw 20],...
                'String',rlbl{i},'FontSize',9,'Value',i==1,'UserData',i-1,...
                'Callback','set(findobj(gcbf,''Style'',''radiobutton''),''Value'',0);set(gcbo,''Value'',1)');
        end
        msgb = uicontrol(d,'Style','edit','Position',[20 40 460 30],'Max',4,'Enable','inactive', ...
            'HorizontalAlignment','left','BackgroundColor','white','FontSize',9, ...
            'String',{'Select a resolution and pose...'});
        setappdata(0,'workspace_message_box',msgb);
        uicontrol(d,'Style','pushbutton','String','Cancel','Position',[190 10 120 25], ...
            'Callback',@(~,~)delete(d));

    case 'draw_workspace_me'
        d = dialog('Position',[450 500 580 240], 'Name','Orientation Workspace PNG Output');
        movegui(d,'center');
        % Instruction
        uicontrol(d,'Style','text','Units','pixels', ...
            'Position',[20 125 540 105], ...
            'String',{...
            'Use NEW or RECALL ORIENTATION WORKSPACE solution and export PNG to output folder?';...
            'If YES, select file and input number images to output between 1 and 360 differently angled views.';...
            '';...
            'For example:';...
            'Number of images = 90 → output 90 images at 4° increments (4°–360°) around center';...
            'Number of images = 45 → output 45 images at 8° increments (8°–360°) around center';...
            'Number of images = 1 → output 1 image at the standard view';...
            }, 'HorizontalAlignment','left','FontSize',9);
        % Evenly spaced y's
        ys = [80, 50, 20];
        % NEW/RECALL radio
        bg = uibuttongroup(d,'Units','pixels','Position',[60 ys(1) 475 25],'BorderType','none');
        uicontrol(bg,'Style','radiobutton','Units','pixels', ...
            'Position',[0 0 245 25],'String','orientation_workspace_data_RECALL.mat','Value',1);
        uicontrol(bg,'Style','radiobutton','Units','pixels', ...
            'Position',[245 0 245 25],'String','orientation_workspace_data_NEW.mat');
        % ANGULAR_STEP input
        uicontrol(d,'Style','text','Units','pixels', ...
            'Position',[150-130 ys(2) 150 25],'String','Number of images =', ...
            'HorizontalAlignment','right','FontSize',9);
        input_box = uicontrol(d,'Style','edit','Units','pixels', ...
            'Position',[305-130 ys(2)+5 110 25],'BackgroundColor','white', ...
            'HorizontalAlignment','center','FontSize',9);
        % Yes / No
        cbYes = @(~,~) yes_callback( input_box, d, 0,...
            strcmp(bg.SelectedObject.String,'orientation_workspace_data_NEW.mat') );
        uicontrol(d,'Style','pushbutton','Units','pixels','Position',[180 ys(3) 100 30], ...
            'String','Plot and Export','Callback',cbYes);
        uicontrol(d,'Style','pushbutton','Units','pixels','Position',[300 ys(3) 100 30], ...
            'String','Cancel','Callback',@(s,e) delete(d));

    case 'draw_reachable_workspace_me'
        d = dialog('Position',[450 500 580 240], 'Name','Reachable Workspace PNG Output');
        movegui(d,'center');
        % Instruction
        uicontrol(d,'Style','text','Units','pixels', ...
            'Position',[20 125 540 105], ...
            'String',{...
            'Use NEW or RECALL REACHABLE WORKSPACE solution and export PNG to output folder?';...
            'If YES, select file and input angular step between 1 and 360 for successive views.';...
            '';...
            'For example:';...
            'Number of images = 90 → output 90 images at 4° increments (4°–360°) around center';...
            'Number of images = 45 → output 45 images at 8° increments (8°–360°) around center';...
            'Number of images = 1 → output 1 image at the standard view';...
            }, 'HorizontalAlignment','left','FontSize',9);
        ys = [80, 50, 20];
        % NEW/RECALL radio
        bg = uibuttongroup(d,'Units','pixels','Position',[60 ys(1) 475 25],'BorderType','none');
        uicontrol(bg,'Style','radiobutton','Units','pixels', ...
            'Position',[0 0 245 25],'String','reachable_workspace_data_RECALL.mat','Value',1);
        uicontrol(bg,'Style','radiobutton','Units','pixels', ...
            'Position',[245 0 245 25],'String','reachable_workspace_data_NEW.mat');
        % ANGULAR_STEP input
        uicontrol(d,'Style','text','Units','pixels', ...
            'Position',[150-130 ys(2) 150 25],'String','Number of images =', ...
            'HorizontalAlignment','right','FontSize',9);
        input_box = uicontrol(d,'Style','edit','Units','pixels', ...
            'Position',[305-130 ys(2)+5 110 25],'BackgroundColor','white', ...
            'HorizontalAlignment','center','FontSize',9);
        % Yes / No
        cbYes = @(~,~) yes_callback( input_box, d, 1, ...
            strcmp(bg.SelectedObject.String,'reachable_workspace_data_NEW.mat') );
        uicontrol(d,'Style','pushbutton','Units','pixels','Position',[180 ys(3) 100 30], ...
            'String','Plot and Export','Callback',cbYes);
        uicontrol(d,'Style','pushbutton','Units','pixels','Position',[300 ys(3) 100 30], ...
            'String','Cancel','Callback',@(s,e) delete(d));

    case 'overwrite_me'
        overwrite_data(); disp('current pose overwritten... SAVE if you want to keep this pose...');

    case 'save_me'
        save_data(); disp('configuration saved...');

    case 'zero_me'
        zero_data(); disp('new input data zeroed...');

    case 'home_me'
        home_data(); disp('new input data given home values...');

    case 'quit'
        % Shared by the Quit button, the Escape key and the window close
        % button (CloseRequestFcn).  Closes at once when nothing has changed
        % since start-up or since the last Save Everything; otherwise asks.
        fig = gcbf;
        if isempty(fig), fig = gcf; end
        pi = get(fig,'UserData');
        if isfield(pi,'saved_signature') && strcmp(pi.saved_signature, state_signature(fig))
            disp('quitting (nothing changed since the last save)...');
            delete(fig);
            return;
        end
        reply = questdlg( ...
            'Quit with or without saving?', 'Quit', ...
            'Quit with saving','Quit without saving','Cancel', ...
            'Quit with saving');
        switch reply
            case 'Quit with saving'
                set(0,'CurrentFigure',fig);
                save_data(); disp('configuration saved...'); disp('quitting...');
                delete(fig);
            case 'Quit without saving'
                disp('quitting without saving...');
                delete(fig);
            otherwise  % 'Cancel' or closed dialog: do nothing
        end

end
end


function normalise_numeric_box(h)
%NORMALISE_NUMERIC_BOX  Round an edited value box to three decimals.
%   Surrounding whitespace / newlines (spreadsheet cells) are tolerated; a
%   value that is not a number is reset to 0.000 with a console message.
    if isempty(h) || ~ishghandle(h), return; end
    raw = strtrim(get(h, 'String'));
    if iscell(raw), raw = strjoin(raw, ' '); end
    v = str2double(strrep(raw, char(8722), '-'));   % Unicode minus -> ASCII
    if isnan(v) || ~isfinite(v)
        fprintf('Not a number: "%s" reset to 0.000\n', raw);
        v = 0;
    end
    set(h, 'String', sprintf('%.3f', round(v, 3)));
end


function escape_to_quit(evt, myname)
%ESCAPE_TO_QUIT  Escape anywhere in the main window acts like the Quit button.
    if strcmp(evt.Key, 'escape')
        feval(myname, 'quit');
    end
end
