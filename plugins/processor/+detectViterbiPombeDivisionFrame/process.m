function [paramout, dataout, imageout] = process(param, roiobj, ctx)
% detectViterbiPombeDivisionFrame.process  Pipeline-compatible wrapper.

if nargin < 3
    ctx = struct();
elseif ~isstruct(ctx)
    ctx = struct('frames', ctx);
end

if nargin == 0 || isempty(param)
    paramout = detectViterbiPombeDivisionFrame.setparam(ctx);
    dataout = [];
    imageout = [];
    return;
end

paramout = normalizeParamLocal(param);
paramout = applyOutputNameFallback(paramout, ctx);

frames = [];
if isfield(ctx, 'frames') && ~isempty(ctx.frames)
    frames = ctx.frames;
elseif isfield(ctx, 'sel') && isstruct(ctx.sel) && isfield(ctx.sel, 'frames') && ~isempty(ctx.sel.frames)
    frames = ctx.sel.frames;
end

[paramout, dataout, imageout] = detectViterbiPombeDivisionFrame.core(paramout, roiobj, frames);
end

function paramout = normalizeParamLocal(param)
paramout = param;
defs = detectViterbiPombeDivisionFrame.setparam();
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

function paramout = applyOutputNameFallback(paramout, ctx)
outputName = '';
if isfield(ctx, 'outputName') && ~isempty(ctx.outputName)
    outputName = char(string(ctx.outputName));
elseif isfield(ctx, 'names') && isstruct(ctx.names) && isfield(ctx.names, 'outputName') && ~isempty(ctx.names.outputName)
    outputName = char(string(ctx.names.outputName));
end
if isempty(outputName)
    return;
end

if ~isfield(paramout, 'outputMaskChannelName') || isempty(strtrim(char(string(paramout.outputMaskChannelName))))
    paramout.outputMaskChannelName = outputName;
end
if ~isfield(paramout, 'profileSeriesName') || isempty(strtrim(char(string(paramout.profileSeriesName))))
    paramout.profileSeriesName = [outputName '_profile'];
end
if ~isfield(paramout, 'scoreSeriesName') || isempty(strtrim(char(string(paramout.scoreSeriesName))))
    paramout.scoreSeriesName = [outputName '_score'];
end
end
