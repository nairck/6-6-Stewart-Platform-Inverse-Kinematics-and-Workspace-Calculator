function axes = rpy_axes_of(pinfo)
%RPY_AXES_OF  The roll/pitch/yaw axes assignment stored in the main figure's
%   UserData ('XYZ' when not set).
if isfield(pinfo, 'rpy_axes') && ~isempty(pinfo.rpy_axes)
    axes = upper(char(pinfo.rpy_axes));
else
    axes = 'XYZ';
end
end
