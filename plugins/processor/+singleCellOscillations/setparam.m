function paramout = setparam(ctx)
% singleCellOscillations.setparam  Parameters for cycle-normalized fluorescence.

if nargin < 1 || isempty(ctx)
    ctx = struct();
end

paramout = struct();
paramout.classification_data = 'div_1';
paramout.fluorescence_data = 'channel_quantification';
paramout.labelVariable = 'div_1 / labels';
paramout.fluorescenceVariable = 'channel_quantification / Ratio_Mean_NoBckg_channel001_z001_channel002_z001_cyto';
paramout.cellValueReducer = 'mean';

paramout.baselineMethod = 'moving_mean';
paramout.baselineWindow = 50;
paramout.baselineEndpoints = 'shrink';

paramout.minCycleLength = 10;
paramout.maxCycleLength = 200;
paramout.normFrames = 100;
paramout.interpolationMethod = 'linear';
paramout.allowExtrapolation = true;

paramout.traceOutputName = 'osc_detrended_trace';
paramout.normalizedCyclesOutputName = 'osc_normalized_cycles';
paramout.cycleMetadataOutputName = 'osc_cycle_metadata';

paramout.writeArtifacts = false;
paramout.verbose = true;

if isstruct(ctx) && isfield(ctx, 'params') && isstruct(ctx.params)
    paramout = mergeStruct(paramout, ctx.params);
end

paramout.tip = { ...
    'Classification dataseries groupid, typically div_1', ...
    'Fluorescence/metrics dataseries groupid, typically channel_quantification', ...
    'Classification dataseries variable binding, e.g. div_1 / labels', ...
    'Fluorescence dataseries variable binding, e.g. channel_quantification / Ratio_Mean_NoBckg_channel001_z001_channel002_z001_cyto', ...
    'How to reduce per-frame cell vectors: mean, median, first, max, min', ...
    'Baseline method: moving_mean, moving_median, none', ...
    'Moving baseline window in frames', ...
    'MATLAB moving-window endpoint handling: shrink or fill; legacy_discard reproduces old script alignment only when possible', ...
    'Minimum accepted cycle length in frames', ...
    'Maximum accepted cycle length in frames', ...
    'Number of normalized intra-cycle time points', ...
    'Interpolation method passed to interp1, typically linear or pchip', ...
    'Allow extrapolation when a cycle has fewer points than normFrames', ...
    'Output temporal dataseries with source-frame detrended trace', ...
    'Output temporal dataseries with normalized intra-cycle traces', ...
    'Output generation dataseries with one row per detected cycle candidate', ...
    'Write run-level workbook and MAT artifact tables under the project root', ...
    'Print progress messages' ...
    };
end

function out = mergeStruct(base, override)
out = base;
names = fieldnames(override);
for i = 1:numel(names)
    out.(names{i}) = override.(names{i});
end
end
