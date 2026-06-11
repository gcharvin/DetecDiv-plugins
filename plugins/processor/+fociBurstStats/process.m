function [paramout, dataout, imageout] = process(param, roiobj, ctx)
% fociBurstStats.process  Pipeline-compatible wrapper.

if nargin < 3 || isempty(ctx)
    ctx = struct();
elseif ~isstruct(ctx)
    ctx = struct('frames', ctx);
end

if nargin == 0 || isempty(param)
    paramout = fociBurstStats.setparam(ctx);
    dataout = [];
    imageout = [];
    return;
end

ctxWithParams = ctx;
ctxWithParams.params = param;
paramout = localMerge(fociBurstStats.setparam(ctxWithParams), param);

[paramout, dataout, imageout] = fociBurstStats.core(paramout, roiobj, ctx);
end

function out = localMerge(base, override)
out = base;
if ~isstruct(override)
    out = override;
    return;
end
names = fieldnames(override);
for i = 1:numel(names)
    out.(names{i}) = override.(names{i});
end
end
