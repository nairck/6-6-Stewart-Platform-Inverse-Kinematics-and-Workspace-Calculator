function [M, e] = frame_transition(originFrom, originTo, axes)
%FRAME_TRANSITION  (M, e) taking coordinates in originFrom's frame to
%   originTo's frame: q_to = M * q_from + e, with M = R_to' * R_from and
%   e = R_to' * (d_from - d_to) (both origins relative to Origin 1, see
%   origin_frame.m).  M is a proper rotation.
if nargin < 3 || isempty(axes), axes = 'XYZ'; end
[Ra, da] = origin_frame(originFrom, axes);
[Rb, db] = origin_frame(originTo, axes);
M = Rb' * Ra;
e = Rb' * (da - db);
end
