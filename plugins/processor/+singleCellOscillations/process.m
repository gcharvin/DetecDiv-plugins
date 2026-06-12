function [paramout, dataout, imageout] = process(param, roiobj, ctx)
% singleCellOscillations.process  Pipeline-compatible wrapper.

if nargin < 3 || isempty(ctx)
    ctx = struct();
elseif ~isstruct(ctx)
    ctx = struct('frames', ctx);
end

if nargin == 0 || isempty(param)
    paramout = singleCellOscillations.setparam(ctx);
    dataout = [];
    imageout = [];
    return;
end

ctxWithParams = ctx;
ctxWithParams.params = param;
paramout = localMerge(singleCellOscillations.setparam(ctxWithParams), param);

[paramout, dataout, imageout] = singleCellOscillations.core(paramout, roiobj, ctx);
end

function out = localMerge(base, override)
out = base;
if ~isstruct(override)
    return;
end
names = fieldnames(override);
for i = 1:numel(names)
    out.(names{i}) = override.(names{i});
end
end
