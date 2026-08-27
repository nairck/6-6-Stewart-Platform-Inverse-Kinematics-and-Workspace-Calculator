function out = last_save_dir(newPath)
%LAST_SAVE_DIR  Remembered save location shared by every file dialog.
%   last_save_dir()        -> the folder the next dialog should open in
%   last_save_dir(path)    -> remember the folder of a file (or a folder)
%   The first dialog starts in the program's folder; afterwards the folder
%   last used anywhere is returned, or its nearest existing parent, or the
%   program's folder again if none exists.
persistent lastDir
if nargin >= 1
    if isfolder(newPath), lastDir = newPath; else, lastDir = fileparts(newPath); end
    out = lastDir;
    return;
end
start = fileparts(mfilename('fullpath'));
if isempty(start) || ~isfolder(start), start = pwd; end
p = lastDir;
while ~isempty(p) && ~isfolder(p)
    parent = fileparts(p);
    if strcmp(parent, p), p = ''; break; end
    p = parent;
end
if isempty(p), out = start; else, out = p; end
end
