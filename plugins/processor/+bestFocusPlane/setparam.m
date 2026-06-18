function paramout = setparam(ctx)
% bestFocusPlane.setparam  Defaults for ROI-local best focal plane extraction.

if nargin < 1 || isempty(ctx)
    ctx = struct();
end

paramout = struct();
paramout.channels = {};
paramout.outputChannelName = 'DIC_focus';
paramout.zBestOutputName = 'DIC_focus_best_z';
paramout.focusSmoothZ = 5;
paramout.focusProjectionRadius = 0;
paramout.focusCenterCrop = 1.0;
paramout.overwrite = true;
paramout.verbose = true;

if isstruct(ctx) && isfield(ctx, 'params') && isstruct(ctx.params)
    paramout = mergeStruct(paramout, ctx.params);
end

paramout.tip = { ...
    'Input ROI image channels to treat as one z-stack; empty means ctx.channels or all ROI channels', ...
    'Output ROI image channel containing the selected focal plane per frame', ...
    'Output dataseries groupid storing zBest and focus scores per frame', ...
    'Moving average smoothing window along z before argmax', ...
    'Average planes zBest +/- radius instead of taking only zBest; 0 means single plane', ...
    'Centered crop fraction used for focus scoring; 1 uses full ROI', ...
    'Replace an existing output channel/dataseries with the same names', ...
    'Print one-line progress per ROI' ...
    };
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
