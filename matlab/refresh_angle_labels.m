function refresh_angle_labels(mainFig)
%REFRESH_ANGLE_LABELS  Constraint labels say which axis each angle rotates about.
pinfo = get(mainFig, 'UserData');
if ~isfield(pinfo, 'lbl_roll'), return; end
axes = rpy_axes_of(pinfo);
set(pinfo.lbl_roll,  'String', sprintf('Roll [° about %s]:',  lower(axes(1))));
set(pinfo.lbl_pitch, 'String', sprintf('Pitch [° about %s]:', lower(axes(2))));
set(pinfo.lbl_yaw,   'String', sprintf('Yaw [° about %s]:',   lower(axes(3))));
end
