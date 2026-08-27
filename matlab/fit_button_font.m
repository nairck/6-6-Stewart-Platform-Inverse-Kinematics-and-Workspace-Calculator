function fit_button_font(h, lines, widthPx, heightPx, maxPt, minPt)
%FIT_BUTTON_FONT  Put multi-line text on a push/toggle button and size the font.
%
%   A MATLAB push or toggle button shows only the FIRST line of a cell-array
%   label, so multi-line labels must be given as HTML (<br> between lines),
%   which the underlying Swing control renders; single-line labels are set as
%   plain text.  The font is then shrunk (like the Python _fit_text) until the
%   widest line fits widthPx, allowing for the button's own margins, and all
%   lines fit heightPx.
%
%   h        : push or toggle button handle
%   lines    : char row or cell array of lines
%   widthPx  : button width  [px]
%   heightPx : button height [px]
if nargin < 5 || isempty(maxPt), maxPt = 8.5; end
if nargin < 6 || isempty(minPt), minPt = 5.5; end
if ischar(lines), lines = {lines}; end
lines = lines(:)';
widest = max(cellfun(@length, lines));
pt = maxPt;
while pt > minPt && (widest * pt * 0.62 > widthPx - 14 || numel(lines) * pt * 1.7 > heightPx - 6)
    pt = pt - 0.5;
end
set(h, 'FontSize', pt);
if numel(lines) == 1
    set(h, 'String', lines{1});
else
    esc = cellfun(@escape_html, lines, 'Uni', false);
    set(h, 'String', ['<html><div style="text-align:center">' strjoin(esc, '<br>') '</div></html>']);
end
end


function out = escape_html(s)
out = strrep(char(s), '&', '&amp;');
out = strrep(out, '<', '&lt;');
out = strrep(out, '>', '&gt;');
end
