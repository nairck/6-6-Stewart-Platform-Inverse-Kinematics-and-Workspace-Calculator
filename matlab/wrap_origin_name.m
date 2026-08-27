function out = wrap_origin_name(name, width)
%WRAP_ORIGIN_NAME  Wrap an origin name once for the table's first column
%   (identical rule to the Python adj_table.wrap_name): only when longer than
%   width and containing a space; the break is the last space that keeps the
%   first line within width, or the first space if none does.  A single word
%   is never broken.  Returns a cell array of one or two lines.
if nargin < 2 || isempty(width), width = 7; end
name = char(name);
spaces = find(name == ' ');
if numel(name) <= width || isempty(spaces)
    out = {name};
    return;
end
fitting = spaces(spaces - 1 <= width);
if isempty(fitting), s = spaces(1); else, s = fitting(end); end
out = {strtrim(name(1:s-1)), strtrim(name(s+1:end))};
end
