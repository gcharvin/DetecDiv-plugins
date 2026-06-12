function [paramout, dataout, imageout] = core(param, roiobj, ctx)
% singleCellOscillations.core  Detrend and normalize fluorescence cycles.

imageout = [];

if nargin == 0 || isempty(param)
    paramout = singleCellOscillations.setparam(struct());
    dataout = [];
    return;
end
if nargin < 3 || isempty(ctx) || ~isstruct(ctx)
    ctx = struct();
end

paramout = normalizeParams(param, ctx);

if isempty(roiobj)
    dataout = [];
    return;
end

if shouldLoadData(roiobj)
    try
        roiobj.load('data', 'Silent');
    catch
        try
            roiobj.load('data');
        catch ME
            warning('singleCellOscillations:LoadDataFailed', ...
                'Could not load ROI data: %s', ME.message);
        end
    end
end

dataout = roiobj.data;
if isempty(dataout)
    dataout = dataseries;
end

roiId = makeRoiId(roiobj);
[traceTable, normalizedTable, metadataTable, status] = computeOneRoi(roiobj, paramout);

dataout = upsertDataSeries(dataout, roiobj, paramout.traceOutputName, traceTable, ...
    "temporal", 'Detrended fluorescence trace for single-cell oscillation analysis.', ...
    tracePlotSpec(traceTable), paramout, status);
dataout = upsertDataSeries(dataout, roiobj, paramout.normalizedCyclesOutputName, normalizedTable, ...
    "temporal", 'Cycle-normalized detrended fluorescence traces.', ...
    normalizedPlotSpec(normalizedTable), paramout, status);
dataout = upsertDataSeries(dataout, roiobj, paramout.cycleMetadataOutputName, metadataTable, ...
    "generation", 'One row per detected cell-cycle candidate.', ...
    metadataPlotSpec(metadataTable), paramout, status);

if paramout.writeArtifacts
    writeArtifacts(paramout, roiId, traceTable, normalizedTable, metadataTable);
end

if paramout.verbose
    fprintf('[singleCellOscillations] ROI %s | status=%s | accepted cycles=%d\n', ...
        roiId, char(status), sum(metadataTable.accepted));
end
end

function paramout = normalizeParams(param, ctx)
defaults = singleCellOscillations.setparam(ctx);
paramout = mergeStruct(defaults, param);

paramout.classification_data = nonemptyChar(paramout.classification_data, 'div_1');
paramout.fluorescence_data = nonemptyChar(paramout.fluorescence_data, 'channel_quantification');
paramout.labelColumn = nonemptyChar(paramout.labelColumn, 'labels');
paramout.fluorescenceColumn = nonemptyChar(paramout.fluorescenceColumn, '');
paramout.cellValueReducer = validatestring(lower(nonemptyChar(paramout.cellValueReducer, 'mean')), ...
    {'mean','median','first','max','min'});

paramout.frameStart = optionalPositiveInteger(paramout.frameStart);
paramout.frameEnd = optionalPositiveInteger(paramout.frameEnd);
paramout.framePeriod = numericScalar(paramout.framePeriod, 1);
if paramout.framePeriod <= 0 || isnan(paramout.framePeriod)
    paramout.framePeriod = 1;
end
paramout.timeUnit = validatestring(nonemptyChar(paramout.timeUnit, 'frames'), {'frames','s','min','h'});

paramout.baselineMethod = validatestring(lower(nonemptyChar(paramout.baselineMethod, 'moving_mean')), ...
    {'moving_mean','moving_median','none'});
paramout.baselineWindow = max(1, round(numericScalar(paramout.baselineWindow, 50)));
paramout.baselineEndpoints = validatestring(lower(nonemptyChar(paramout.baselineEndpoints, 'shrink')), ...
    {'shrink','fill','legacy_discard'});

paramout.cycleBoundaryMode = validatestring(lower(nonemptyChar(paramout.cycleBoundaryMode, 'label_transition')), ...
    {'label_transition'});
paramout.transitionFrom = nonemptyChar(paramout.transitionFrom, 'large');
paramout.transitionTo = nonemptyChar(paramout.transitionTo, 'small');
paramout.minCycleLength = max(1, round(numericScalar(paramout.minCycleLength, 10)));
paramout.maxCycleLength = max(paramout.minCycleLength, round(numericScalar(paramout.maxCycleLength, 200)));
paramout.normFrames = max(2, round(numericScalar(paramout.normFrames, 100)));
paramout.interpolationMethod = validatestring(lower(nonemptyChar(paramout.interpolationMethod, 'linear')), ...
    {'linear','pchip','spline','nearest'});
paramout.allowExtrapolation = logicalScalar(paramout.allowExtrapolation, true);

paramout.traceOutputName = nonemptyChar(paramout.traceOutputName, 'osc_detrended_trace');
paramout.normalizedCyclesOutputName = nonemptyChar(paramout.normalizedCyclesOutputName, 'osc_normalized_cycles');
paramout.cycleMetadataOutputName = nonemptyChar(paramout.cycleMetadataOutputName, 'osc_cycle_metadata');
paramout.writeArtifacts = logicalScalar(paramout.writeArtifacts, false);
paramout.outputDir = nonemptyChar(paramout.outputDir, '');
if isempty(paramout.outputDir)
    paramout.outputDir = pwd;
end
paramout.workbookName = nonemptyChar(paramout.workbookName, 'single_cell_oscillations.xlsx');
paramout.runId = resolveRunId(paramout, ctx);
paramout.verbose = logicalScalar(paramout.verbose, true);
end

function [traceTable, normalizedTable, metadataTable, status] = computeOneRoi(roiobj, opt)
traceTable = emptyTraceTable();
normalizedTable = emptyNormalizedTable();
metadataTable = emptyMetadataTable();

classDs = pickDataSeries(roiobj, opt.classification_data);
fluoDs = pickDataSeries(roiobj, opt.fluorescence_data);

if isempty(classDs)
    status = "missing_classification_dataseries";
    return;
end
if isempty(fluoDs)
    status = "missing_fluorescence_dataseries";
    return;
end
if ~istable(classDs.data) || height(classDs.data) == 0
    status = "empty_classification_dataseries";
    return;
end
if ~istable(fluoDs.data) || height(fluoDs.data) == 0
    status = "empty_fluorescence_dataseries";
    return;
end

[labels, labelOk] = extractLabels(classDs, opt.labelColumn);
if ~labelOk
    status = "missing_label_column";
    return;
end

[rawFluo, fluoOk] = extractFluorescence(fluoDs, opt.fluorescenceColumn, opt.cellValueReducer);
if ~fluoOk
    status = "missing_fluorescence_column";
    return;
end

n = min(numel(labels), numel(rawFluo));
labels = labels(1:n);
rawFluo = rawFluo(1:n);
sourceFrames = (1:n)';

frameMask = true(n, 1);
if ~isempty(opt.frameStart)
    frameMask = frameMask & sourceFrames >= opt.frameStart;
end
if ~isempty(opt.frameEnd)
    frameMask = frameMask & sourceFrames <= opt.frameEnd;
end
if ~any(frameMask)
    status = "empty_frame_selection";
    return;
end

baseline = computeBaseline(rawFluo, frameMask, opt);
detrended = rawFluo - baseline;
valid = frameMask & ~isnan(rawFluo) & ~isnan(detrended) & labels ~= "";

sel = find(frameMask);
traceTable = table( ...
    sourceFrames(sel), ...
    (sourceFrames(sel) - 1) .* opt.framePeriod, ...
    rawFluo(sel), ...
    baseline(sel), ...
    detrended(sel), ...
    categorical(labels(sel)), ...
    valid(sel), ...
    zeros(numel(sel), 1), ...
    'VariableNames', {'frame','time','raw_fluorescence','baseline','detrended_fluorescence','classification','valid','cycle_index'});

[metadataTable, normalizedTable, cycleIndexByFrame] = detectAndNormalizeCycles(sourceFrames, labels, detrended, valid, frameMask, opt);
if ~isempty(cycleIndexByFrame)
    [isMember, loc] = ismember(traceTable.frame, sourceFrames);
    traceTable.cycle_index(isMember) = cycleIndexByFrame(loc(isMember));
end

if height(metadataTable) == 0
    status = "no_cycle_candidates";
elseif any(metadataTable.accepted)
    status = "ok";
else
    status = "no_accepted_cycles";
end
end

function baseline = computeBaseline(rawFluo, frameMask, opt)
baseline = nan(size(rawFluo));
switch opt.baselineMethod
    case 'none'
        baseline(:) = 0;
    case 'moving_median'
        baseline = movmedian(rawFluo, opt.baselineWindow, 'omitnan', 'Endpoints', movingEndpoint(opt.baselineEndpoints));
    otherwise
        if strcmp(opt.baselineEndpoints, 'legacy_discard')
            b = movmean(rawFluo, opt.baselineWindow, 'omitnan', 'Endpoints', 'discard');
            if numel(b) == sum(frameMask)
                baseline(frameMask) = b(:);
            else
                baseline = movmean(rawFluo, opt.baselineWindow, 'omitnan', 'Endpoints', 'shrink');
            end
        else
            baseline = movmean(rawFluo, opt.baselineWindow, 'omitnan', 'Endpoints', movingEndpoint(opt.baselineEndpoints));
        end
end
end

function endpoint = movingEndpoint(value)
if strcmp(value, 'legacy_discard')
    endpoint = 'shrink';
else
    endpoint = value;
end
end

function [metadataTable, normalizedTable, cycleIndexByFrame] = detectAndNormalizeCycles(frames, labels, detrended, valid, frameMask, opt)
metadataTable = emptyMetadataTable();
normalizedTable = emptyNormalizedTable();
cycleIndexByFrame = zeros(size(frames));

workIdx = find(frameMask);
workLabels = labels(workIdx);
transitionsLocal = find(workLabels(1:end-1) == string(opt.transitionFrom) & workLabels(2:end) == string(opt.transitionTo));
if isempty(transitionsLocal)
    return;
end
transitions = workIdx(transitionsLocal);

metaRows = cell(max(numel(transitions) - 1, 0), 1);
normRows = cell(max(numel(transitions) - 1, 0), 1);
acceptedCount = 0;

for c = 1:(numel(transitions) - 1)
    startIdx = transitions(c);
    endIdx = transitions(c + 1) - 1;
    idx = (startIdx:endIdx)';
    cycleLength = numel(idx);
    rejectReason = "";
    accepted = true;
    if cycleLength < opt.minCycleLength
        accepted = false;
        rejectReason = "too_short";
    elseif cycleLength > opt.maxCycleLength
        accepted = false;
        rejectReason = "too_long";
    elseif ~all(valid(idx))
        accepted = false;
        rejectReason = "invalid_signal_or_label";
    end

    if accepted
        acceptedCount = acceptedCount + 1;
        cycleIndex = acceptedCount;
        cycleIndexByFrame(idx) = cycleIndex;
    else
        cycleIndex = c;
    end

    values = detrended(idx);
    amp = max(values, [], 'omitnan') - min(values, [], 'omitnan');
    metaRows{c} = table(cycleIndex, frames(startIdx), frames(endIdx), cycleLength, ...
        cycleLength .* opt.framePeriod, accepted, string(rejectReason), ...
        mean(values, 'omitnan'), median(values, 'omitnan'), min(values, [], 'omitnan'), ...
        max(values, [], 'omitnan'), amp, trapz(values), ...
        'VariableNames', {'cycle_index','start_frame','end_frame','duration_frames','duration_time', ...
        'accepted','reject_reason','mean_detrended_fluorescence','median_detrended_fluorescence', ...
        'min_detrended_fluorescence','max_detrended_fluorescence','amplitude_detrended_fluorescence', ...
        'auc_detrended_fluorescence'});

    if accepted
        normRows{c} = normalizeCycle(cycleIndex, frames(idx), values, cycleLength, opt);
    end
end

if ~isempty(metaRows)
    metadataTable = vertcat(metaRows{~cellfun(@isempty, metaRows)});
end
if ~isempty(normRows) && any(~cellfun(@isempty, normRows))
    normalizedTable = vertcat(normRows{~cellfun(@isempty, normRows)});
end
end

function T = normalizeCycle(cycleIndex, sourceFrames, values, cycleLength, opt)
x = (1:numel(values))';
xq = linspace(1, numel(values), opt.normFrames)';
if opt.allowExtrapolation
    yq = interp1(x, values(:), xq, opt.interpolationMethod, 'extrap');
else
    yq = interp1(x, values(:), xq, opt.interpolationMethod);
end
sourceFrameInterp = interp1(x, double(sourceFrames(:)), xq, 'linear', 'extrap');
mn = min(yq, [], 'omitnan');
mx = max(yq, [], 'omitnan');
if mx > mn
    yq01 = (yq - mn) ./ (mx - mn);
else
    yq01 = zeros(size(yq));
end

T = table( ...
    repmat(cycleIndex, opt.normFrames, 1), ...
    (1:opt.normFrames)', ...
    linspace(0, 1, opt.normFrames)', ...
    sourceFrameInterp, ...
    repmat(sourceFrames(1), opt.normFrames, 1), ...
    repmat(sourceFrames(end), opt.normFrames, 1), ...
    repmat(cycleLength, opt.normFrames, 1), ...
    yq(:), ...
    yq01(:), ...
    'VariableNames', {'cycle_index','norm_frame','phase','source_frame_interp', ...
    'cycle_start_frame','cycle_end_frame','cycle_length_frames', ...
    'detrended_fluorescence','detrended_fluorescence_norm01'});
end

function [labels, ok] = extractLabels(ds, labelColumn)
ok = false;
labels = strings(0, 1);
vars = string(ds.data.Properties.VariableNames);
idx = find(strcmp(vars, labelColumn), 1);
if isempty(idx) && any(strcmp(vars, "labels"))
    idx = find(strcmp(vars, "labels"), 1);
end
if ~isempty(idx)
    col = ds.data.(char(vars(idx)));
    labels = string(col(:));
    ok = true;
    return;
end

idx = find(strcmp(vars, "id"), 1);
if isempty(idx) || ~isfield(ds.userData, 'classes')
    return;
end
ids = ds.data.(char(vars(idx)));
classes = string(ds.userData.classes(:));
labels = strings(numel(ids), 1);
for i = 1:numel(ids)
    id = double(ids(i));
    if isfinite(id) && id >= 1 && id <= numel(classes)
        labels(i) = classes(id);
    end
end
ok = true;
end

function [signal, ok] = extractFluorescence(ds, columnName, reducer)
ok = false;
signal = [];
vars = string(ds.data.Properties.VariableNames);
idx = find(strcmp(vars, columnName), 1);
if isempty(idx)
    idx = find(contains(vars, columnName), 1);
end
if isempty(idx)
    return;
end

col = ds.data.(char(vars(idx)));
signal = reduceColumn(col, reducer);
ok = true;
end

function signal = reduceColumn(col, reducer)
if isnumeric(col) || islogical(col)
    signal = double(col(:));
    return;
end
if iscell(col)
    signal = nan(numel(col), 1);
    for i = 1:numel(col)
        signal(i) = reduceOneCell(col{i}, reducer);
    end
    return;
end
if isstring(col) || iscategorical(col)
    signal = str2double(string(col(:)));
    return;
end
signal = nan(numel(col), 1);
end

function value = reduceOneCell(item, reducer)
value = NaN;
if isempty(item)
    return;
end
if iscell(item)
    item = [item{:}];
end
if isnumeric(item) || islogical(item)
    vals = double(item(:));
elseif isstring(item) || ischar(item) || iscategorical(item)
    vals = str2double(string(item(:)));
else
    return;
end
vals = vals(~isnan(vals));
if isempty(vals)
    return;
end
switch reducer
    case 'median'
        value = median(vals);
    case 'first'
        value = vals(1);
    case 'max'
        value = max(vals);
    case 'min'
        value = min(vals);
    otherwise
        value = mean(vals);
end
end

function ds = pickDataSeries(roiobj, groupid)
ds = [];
try
    if isempty(roiobj.data)
        return;
    end
    ids = arrayfun(@(x) char(string(x.groupid)), roiobj.data, 'UniformOutput', false);
    idx = find(strcmp(ids, groupid), 1);
    if isempty(idx)
        return;
    end
    ds = roiobj.data(idx);
catch
    ds = [];
end
end

function dataout = upsertDataSeries(dataout, roiobj, groupid, T, dsType, description, plotSpec, opt, status)
idx = [];
try
    idx = find(arrayfun(@(x) strcmp(char(string(x.groupid)), groupid), dataout), 1);
catch
end
if isempty(idx)
    if isscalar(dataout) && isempty(dataout(1).data)
        idx = 1;
    else
        idx = numel(dataout) + 1;
    end
end

if isempty(T)
    T = table();
end
varNames = T.Properties.VariableNames;
ds = dataseries(T, varNames, ...
    'groupid', groupid, 'parentid', makeRoiId(roiobj), ...
    'plot', plotSpec.plot, 'groups', plotSpec.groups);
ds.class = "processing";
ds.type = dsType;
ds.description = description;
ds.userData = struct();
ds.userData.processor = 'singleCellOscillations';
ds.userData.status = char(status);
ds.userData.runId = opt.runId;
ds.userData.source = struct( ...
    'classification_data', opt.classification_data, ...
    'fluorescence_data', opt.fluorescence_data, ...
    'labelColumn', opt.labelColumn, ...
    'fluorescenceColumn', opt.fluorescenceColumn);
ds.userData.parameters = struct( ...
    'frameStart', opt.frameStart, ...
    'frameEnd', opt.frameEnd, ...
    'baselineMethod', opt.baselineMethod, ...
    'baselineWindow', opt.baselineWindow, ...
    'transitionFrom', opt.transitionFrom, ...
    'transitionTo', opt.transitionTo, ...
    'normFrames', opt.normFrames);
dataout(idx) = ds;
end

function spec = tracePlotSpec(T)
spec = plotSpecForVars(T, {'frame','time','raw_fluorescence','baseline','detrended_fluorescence','classification','valid','cycle_index'}, ...
    {'frame','time','fluo','fluo','fluo','label','qc','cycle'}, ...
    {'detrended_fluorescence'});
end

function spec = normalizedPlotSpec(T)
spec = plotSpecForVars(T, {'cycle_index','norm_frame','phase','source_frame_interp','cycle_start_frame','cycle_end_frame','cycle_length_frames','detrended_fluorescence','detrended_fluorescence_norm01'}, ...
    {'cycle','frame','phase','frame','frame','frame','duration','fluo','fluo_norm'}, ...
    {'detrended_fluorescence'});
end

function spec = metadataPlotSpec(T)
spec = plotSpecForVars(T, {'cycle_index','start_frame','end_frame','duration_frames','duration_time','accepted','reject_reason','mean_detrended_fluorescence','median_detrended_fluorescence','min_detrended_fluorescence','max_detrended_fluorescence','amplitude_detrended_fluorescence','auc_detrended_fluorescence'}, ...
    {'cycle','frame','frame','duration','duration','qc','qc','fluo','fluo','fluo','fluo','fluo','fluo'}, ...
    {'duration_frames'});
end

function spec = plotSpecForVars(T, orderedVars, orderedGroups, plottedVars)
vars = T.Properties.VariableNames;
groups = cell(1, numel(vars));
plotFlags = cell(1, numel(vars));
for i = 1:numel(vars)
    idx = find(strcmp(orderedVars, vars{i}), 1);
    if isempty(idx)
        groups{i} = 'value';
    else
        groups{i} = orderedGroups{idx};
    end
    plotFlags{i} = any(strcmp(plottedVars, vars{i}));
end
spec = struct('plot', {plotFlags}, 'groups', {groups});
end

function writeArtifacts(opt, roiId, traceTable, normalizedTable, metadataTable)
if exist(opt.outputDir, 'dir') ~= 7
    mkdir(opt.outputDir);
end
safeRunId = matlab.lang.makeValidName(opt.runId);
safeRoiId = matlab.lang.makeValidName(roiId);
matPath = fullfile(opt.outputDir, [safeRunId '_' safeRoiId '_single_cell_oscillations.mat']);
save(matPath, 'traceTable', 'normalizedTable', 'metadataTable');

workbook = fullfile(opt.outputDir, opt.workbookName);
try
    writetable(traceTable, workbook, 'Sheet', sheetName(safeRoiId, 'trace'));
    writetable(normalizedTable, workbook, 'Sheet', sheetName(safeRoiId, 'cycles'));
    writetable(metadataTable, workbook, 'Sheet', sheetName(safeRoiId, 'metadata'));
catch ME
    warning('singleCellOscillations:WriteArtifactsFailed', ...
        'Could not write Excel artifact: %s', ME.message);
end
end

function name = sheetName(prefix, suffix)
name = [char(prefix) '_' char(suffix)];
name = regexprep(name, '[:\\/?*\[\]]', '_');
if strlength(string(name)) > 31
    suffix = char(suffix);
    keep = max(1, 31 - numel(suffix) - 1);
    name = [name(1:min(keep, numel(name))) '_' suffix];
end
end

function T = emptyTraceTable()
T = table(zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    categorical(strings(0,1)), false(0,1), zeros(0,1), ...
    'VariableNames', {'frame','time','raw_fluorescence','baseline','detrended_fluorescence','classification','valid','cycle_index'});
end

function T = emptyNormalizedTable()
T = table(zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'cycle_index','norm_frame','phase','source_frame_interp', ...
    'cycle_start_frame','cycle_end_frame','cycle_length_frames', ...
    'detrended_fluorescence','detrended_fluorescence_norm01'});
end

function T = emptyMetadataTable()
T = table(zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    false(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'cycle_index','start_frame','end_frame','duration_frames','duration_time', ...
    'accepted','reject_reason','mean_detrended_fluorescence','median_detrended_fluorescence', ...
    'min_detrended_fluorescence','max_detrended_fluorescence','amplitude_detrended_fluorescence', ...
    'auc_detrended_fluorescence'});
end

function tf = shouldLoadData(roiobj)
tf = true;
try
    tf = isempty(roiobj.data) || (isscalar(roiobj.data) && isempty(roiobj.data(1).data));
catch
end
end

function id = makeRoiId(roiobj)
id = 'roi';
try
    if isprop(roiobj, 'id') && ~isempty(roiobj.id)
        id = char(string(roiobj.id));
    end
catch
end
end

function runId = resolveRunId(paramout, ctx)
runId = '';
if isfield(paramout, 'runId') && ~isempty(paramout.runId)
    runId = char(string(paramout.runId));
end
if isempty(runId), runId = nestedChar(ctx, {'runId'}); end
if isempty(runId), runId = nestedChar(ctx, {'run','runId'}); end
if isempty(runId), runId = nestedChar(ctx, {'pipeline','runId'}); end
if isempty(runId), runId = ['manual_' char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))]; end
end

function value = nestedChar(s, path)
value = '';
try
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
catch
    value = '';
end
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

function value = nonemptyChar(value, fallback)
if isempty(value)
    value = fallback;
    return;
end
if iscell(value)
    value = value{end};
end
value = char(string(value));
if isempty(strtrim(value))
    value = fallback;
end
end

function value = numericScalar(value, fallback)
if isempty(value)
    value = fallback;
    return;
end
if iscell(value)
    value = value{end};
end
if isstring(value) || ischar(value) || iscategorical(value)
    value = str2double(char(string(value)));
else
    value = double(value);
end
if isempty(value) || ~isscalar(value) || ~isfinite(value)
    value = fallback;
end
end

function value = optionalPositiveInteger(value)
if isempty(value)
    return;
end
value = numericScalar(value, NaN);
if isnan(value) || value < 1
    value = [];
else
    value = round(value);
end
end

function out = logicalScalar(value, fallback)
out = fallback;
if isempty(value)
    return;
end
if iscell(value)
    value = value{end};
end
if islogical(value)
    out = value;
elseif isnumeric(value)
    out = value ~= 0;
else
    txt = strtrim(char(string(value)));
    out = any(strcmpi(txt, {'true','1','yes','on'}));
end
end
