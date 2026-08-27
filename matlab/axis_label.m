function label = axis_label(v)
%AXIS_LABEL  Signed axis label ('+X'..'-Z') for a unit axis vector.
[~, k] = max(abs(v));
letters = 'XYZ';
if v(k) > 0
    label = ['+' letters(k)];
else
    label = ['-' letters(k)];
end
end
