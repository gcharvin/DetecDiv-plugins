function [paramout, dataout, imageout] = process(param, roiobj, ctx)
% bestFocusPlane.process  Add a best-focus ROI channel from a z-stack.

if nargin < 3 || isempty(ctx)
    ctx = struct();
elseif ~isstruct(ctx)
    ctx = struct('frames', ctx);
end

if nargin == 0 || isempty(param)
    paramout = bestFocusPlane.setparam(ctx);
    dataout = [];
    imageout = [];
    return;
end

ctxWithParams = ctx;
ctxWithParams.params = param;
paramout = mergeStruct(bestFocusPlane.setparam(ctxWithParams), param);

[paramout, dataout, imageout] = bestFocusPlane.core(paramout, roiobj, ctx);
end

function out = mergeStruct(base, override)
out = base;
if ~isstruct(override)
    return;
end
names = fieldnames(override);
for i = 1:numel(names)
    out.(names{i}) = override.(names{i});
end
end
