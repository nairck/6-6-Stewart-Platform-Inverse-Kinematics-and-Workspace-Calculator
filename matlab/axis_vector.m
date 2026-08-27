function v = axis_vector(label)
%AXIS_VECTOR  Unit vector for a signed axis label such as '+X' or '-Z'.
k = find('XYZ' == upper(label(2)), 1);
if isempty(k), error('axis_vector:badLabel', 'unknown axis label ''%s''', label); end
v = zeros(1,3);
if label(1) == '-'
    v(k) = -1;
else
    v(k) = 1;
end
end
