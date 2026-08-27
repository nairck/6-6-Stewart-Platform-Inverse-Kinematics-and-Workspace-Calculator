function lines = wrap_button_name(name, maxLines, target)
%WRAP_BUTTON_NAME  Split an origin name over at most maxLines lines for the
%   main window's buttons, breaking only at spaces and never mid-word
%   (identical rule to config.wrap_button_name in the Python version).
%   Greedy fill to about `target` characters a line; a name with no spaces, or
%   one that will not fit in maxLines lines, is returned on a single line and
%   the caller shrinks the font instead.  Never drops text.
if nargin < 2 || isempty(maxLines), maxLines = 2; end
if nargin < 3 || isempty(target), target = 11; end
name = strtrim(char(name));
if isempty(name) || length(name) <= target || ~any(name == ' ')
    lines = {name};
    return;
end
words = strsplit(name);
lines = {};
cur = '';
for k = 1:numel(words)
    if isempty(cur), trial = words{k}; else, trial = [cur ' ' words{k}]; end
    if ~isempty(cur) && length(trial) > target && numel(lines) < maxLines - 1
        lines{end+1} = cur; %#ok<AGROW>
        cur = words{k};
    else
        cur = trial;
    end
end
lines{end+1} = cur;
if numel(lines) > maxLines, lines = {name}; end
end
