function paramout = setparam(ctx)
% singleCellOscillations.setparam  Parameters for cycle-normalized fluorescence.

if nargin < 1 || isempty(ctx)
    ctx = struct();
end

paramout = struct();
paramout.classification_data = 'div_1';
paramout.fluorescence_data = 'channel_quantification';
paramout.labelColumn = 'labels';
paramout.fluorescenceColumn = 'Ratio_Mean_NoBckg_channel002_z001_channel001_z001_cyto';
paramout.cellValueReducer = 'mean';

paramout.frameStart = 25;
paramout.frameEnd = 167;
paramout.framePeriod = 1;
paramout.timeUnit = 'frames';

paramout.baselineMethod = 'moving_mean';
paramout.baselineWindow = 50;
paramout.baselineEndpoints = 'shrink';

paramout.cycleBoundaryMode = 'label_transition';
paramout.transitionFrom = 'large';
paramout.transitionTo = 'small';
paramout.minCycleLength = 10;
paramout.maxCycleLength = 200;
paramout.normFrames = 100;
paramout.interpolationMethod = 'linear';
paramout.allowExtrapolation = true;

paramout.traceOutputName = 'osc_detrended_trace';
paramout.normalizedCyclesOutputName = 'osc_normalized_cycles';
paramout.cycleMetadataOutputName = 'osc_cycle_metadata';

paramout.writeArtifacts = false;
paramout.outputDir = defaultOutputRoot(ctx);
paramout.workbookName = 'single_cell_oscillations.xlsx';
paramout.runId = '';
paramout.verbose = true;

if isstruct(ctx) && isfield(ctx, 'params') && isstruct(ctx.params)
    paramout = mergeStruct(paramout, ctx.params);
end

paramout.tip = { ...
    'Classification dataseries groupid, typically div_1', ...
    'Fluorescence/metrics dataseries groupid, typically channel_quantification', ...
    'Column containing class labels in the classification dataseries', ...
    'Column containing the scalar fluorescence signal or per-frame cell vector', ...
    'How to reduce per-frame cell vectors: mean, median, first, max, min', ...
    'First source frame included in detrending/cycle detection; empty means first available frame', ...
    'Last source frame included in detrending/cycle detection; empty means last available frame', ...
    'Time between frames, expressed in timeUnit', ...
    'Time unit label: frames, s, min, or h', ...
    'Baseline method: moving_mean, moving_median, none', ...
    'Moving baseline window in frames', ...
    'MATLAB moving-window endpoint handling: shrink or fill; legacy_discard reproduces old script alignment only when possible', ...
    'Cycle boundary mode; currently label_transition is the default and supported mode', ...
    'Class before the boundary, typically large', ...
    'Class after the boundary, typically small', ...
    'Minimum accepted cycle length in frames', ...
    'Maximum accepted cycle length in frames', ...
    'Number of normalized intra-cycle time points', ...
    'Interpolation method passed to interp1, typically linear or pchip', ...
    'Allow extrapolation when a cycle has fewer points than normFrames', ...
    'Output temporal dataseries with source-frame detrended trace', ...
    'Output temporal dataseries with normalized intra-cycle traces', ...
    'Output generation dataseries with one row per detected cycle candidate', ...
    'Write run-level workbook and MAT artifact tables', ...
    'Output folder for optional artifacts', ...
    'Excel workbook name for optional artifacts', ...
    'Run id; empty means pipeline run id when available or manual', ...
    'Print progress messages' ...
    };
end

function root = defaultOutputRoot(ctx)
root = '';
try
    if isstruct(ctx)
        root = nestedChar(ctx, {'projectPath'});
        if isempty(root), root = nestedChar(ctx, {'run','projectPath'}); end
        if isempty(root), root = nestedChar(ctx, {'io','projectPath'}); end
        if isempty(root), root = nestedChar(ctx, {'targetRef','projectPath'}); end
    end
catch
    root = '';
end
if ~isempty(root)
    if exist(root, 'dir') == 7
        return;
    end
    [pth, ~, ~] = fileparts(root);
    root = pth;
end
end

function value = nestedChar(s, path)
value = '';
cur = s;
for i = 1:numel(path)
    key = path{i};
    if ~isstruct(cur) || ~isfield(cur, key)
        return;
    end
    cur = cur.(key);
end
if ~isempty(cur)
    value = char(string(cur));
end
end

function out = mergeStruct(base, override)
out = base;
names = fieldnames(override);
for i = 1:numel(names)
    out.(names{i}) = override.(names{i});
end
end
