function reset_sketch_view(mainFig)
%RESET_SKETCH_VIEW  Put the sketch back to its default view: the default angle
%   and the standard fit.  Used by the Reset View button and by a double-click
%   in the sketch, so the two do exactly the same thing.
if nargin < 1 || isempty(mainFig) || ~isgraphics(mainFig), return; end
pinfo = get(mainFig, 'UserData');
if ~isfield(pinfo, 'ax') || ~isgraphics(pinfo.ax), return; end
view(pinfo.ax, [-30, 20]);
axis(pinfo.ax, 'equal');
if isfield(pinfo, 'fit_pts') && ~isempty(pinfo.fit_pts)
    fit_sketch_view(pinfo.ax, pinfo.fit_pts);
end
axis(pinfo.ax, 'vis3d');
end
