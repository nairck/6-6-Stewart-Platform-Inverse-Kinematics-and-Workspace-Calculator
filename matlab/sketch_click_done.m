function sketch_click_done(fig)
%SKETCH_CLICK_DONE  Called after a rotation gesture in the sketch.  A plain
%   drag is left alone; a double-click resets the view exactly as the Reset
%   View button does (MATLAB's own double-click reset runs first and restores
%   an arbitrary earlier camera, so this puts it right).
if ~isgraphics(fig), return; end
if strcmp(get(fig, 'SelectionType'), 'open')
    reset_sketch_view(fig);
end
end
