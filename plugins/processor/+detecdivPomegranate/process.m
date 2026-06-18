function [paramout, dataout, imageout] = process(param, roiobj, ctx)
% detecdivPomegranate.process  Pipeline-compatible wrapper.

if nargin < 3
    ctx = struct();
elseif ~isstruct(ctx)
    ctx = struct('frames', ctx);
end

if nargin == 0 || isempty(param)
    paramout = detecdivPomegranate.setparam(ctx);
    dataout = [];
    imageout = [];
    return;
end

paramout = normalizeParamLocal(param);
[paramout, dataout, imageout] = detecdivPomegranate.core(paramout, roiobj, ctx);
end

function paramout = normalizeParamLocal(param)
paramout = param;
defs = detecdivPomegranate.setparam();
fields = fieldnames(defs);
for i = 1:numel(fields)
    f = fields{i};
    if strcmp(f, 'tip')
        continue;
    end
    if ~isfield(paramout, f) || isempty(paramout.(f))
        paramout.(f) = defs.(f);
    end
end
if ~isfield(paramout, 'tip') && isfield(defs, 'tip')
    paramout.tip = defs.tip;
end
end
