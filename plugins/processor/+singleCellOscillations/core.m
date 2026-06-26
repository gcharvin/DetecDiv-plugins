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
legacyLabelColumn = optionalFieldChar(paramout, 'labelColumn', 'labels');
legacyFluoColumn = optionalFieldChar(paramout, 'fluorescenceColumn', '');
[paramout.classification_data, paramout.labelColumn] = parseDataSeriesVariableBinding( ...
    optionalFieldChar(paramout, 'labelVariable', ''), paramout.classification_data, legacyLabelColumn);
[paramout.fluorescence_data, paramout.fluorescenceColumn] = parseDataSeriesVariableBinding( ...
    optionalFieldChar(paramout, 'fluorescenceVariable', ''), paramout.fluorescence_data, legacyFluoColumn);
paramout.labelVariable = formatDataSeriesVariable(paramout.classification_data, paramout.labelColumn);
paramout.fluorescenceVariable = formatDataSeriesVariable(paramout.fluorescence_data, paramout.fluorescenceColumn);
paramout.cellValueReducer = validatestring(lower(nonemptyChar(paramout.cellValueReducer, 'mean')), ...
    {'mean','median','first','max','min'});
paramout.frames = normalizeFrameSelection(ctx);

paramout.baselineMethod = validatestring(lower(nonemptyChar(paramout.baselineMethod, 'moving_mean')), ...
    {'moving_mean','moving_median','none'});
paramout.baselineWindow = max(1, round(numericScalar(paramout.baselineWindow, 50)));
paramout.baselineEndpoints = validatestring(lower(nonemptyChar(paramout.baselineEndpoints, 'shrink')), ...
    {'shrink','fill','legacy_discard'});

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
paramout.artifactRoot = resolveProjectRoot(ctx);
paramout.artifactWorkbook = 'single_cell_oscillations.xlsx';
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
frameMask = frameMaskFromSelection(opt.frames, sourceFrames);
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
    sourceFrames(sel), ...
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
transitionsLocal = find(workLabels(1:end-1) == "large" & workLabels(2:end) == "small");
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
        cycleLength, accepted, string(rejectReason), ...
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
columnName = strtrim(string(columnName));
idx = [];
if strlength(columnName) > 0 && ~any(strcmpi(columnName, ["auto","<auto>"]))
    idx = find(strcmp(vars, columnName), 1);
end
if isempty(idx) && strlength(columnName) > 0
    idx = find(contains(vars, columnName), 1);
end
if isempty(idx)
    idx = find(contains(vars, "Ratio_Mean_NoBckg", 'IgnoreCase', true), 1);
end
if isempty(idx)
    idx = firstReducibleVariable(ds.data);
end
if isempty(idx)
    return;
end

col = ds.data.(char(vars(idx)));
signal = reduceColumn(col, reducer);
ok = true;
end

function idx = firstReducibleVariable(T)
idx = [];
vars = T.Properties.VariableNames;
for i = 1:numel(vars)
    name = string(vars{i});
    if contains(name, "mask", 'IgnoreCase', true) || contains(name, "idx", 'IgnoreCase', true)
        continue;
    end
    col = T.(vars{i});
    if isnumeric(col) || islogical(col) || iscell(col)
        idx = i;
        return;
    end
end
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
ds.userData.source = struct( ...
    'classification_data', opt.classification_data, ...
    'labelVariable', opt.labelVariable, ...
    'labelColumn', opt.labelColumn, ...
    'fluorescence_data', opt.fluorescence_data, ...
    'fluorescenceVariable', opt.fluorescenceVariable, ...
    'fluorescenceColumn', opt.fluorescenceColumn);
ds.userData.parameters = struct( ...
    'baselineMethod', opt.baselineMethod, ...
    'baselineWindow', opt.baselineWindow, ...
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
if exist(opt.artifactRoot, 'dir') ~= 7
    mkdir(opt.artifactRoot);
end
safeRoiId = matlab.lang.makeValidName(roiId);
matPath = fullfile(opt.artifactRoot, [safeRoiId '_single_cell_oscillations.mat']);
save(matPath, 'traceTable', 'normalizedTable', 'metadataTable');

workbook = fullfile(opt.artifactRoot, opt.artifactWorkbook);
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

function [seriesName, variableName] = parseDataSeriesVariableBinding(binding, fallbackSeries, fallbackVariable)
seriesName = nonemptyChar(fallbackSeries, '');
variableName = nonemptyChar(fallbackVariable, '');
binding = nonemptyChar(binding, '');
if isempty(binding) || any(strcmpi(binding, {'auto','<auto>'}))
    return;
end

parts = regexp(binding, '\s*/\s*', 'split');
if numel(parts) >= 2
    lhs = strtrim(parts{1});
    rhs = strtrim(strjoin(parts(2:end), ' / '));
    if ~isempty(lhs)
        seriesName = lhs;
    end
    if ~isempty(rhs) && ~any(strcmpi(rhs, {'auto','<auto>'}))
        variableName = rhs;
    end
else
    variableName = strtrim(binding);
end
end

function binding = formatDataSeriesVariable(seriesName, variableName)
seriesName = nonemptyChar(seriesName, '');
variableName = nonemptyChar(variableName, '');
if isempty(seriesName)
    binding = variableName;
elseif isempty(variableName)
    binding = seriesName;
else
    binding = [seriesName ' / ' variableName];
end
end

function value = optionalFieldChar(s, name, fallback)
value = fallback;
if isstruct(s) && isfield(s, name)
    value = nonemptyChar(s.(name), fallback);
end
end

function frames = normalizeFrameSelection(ctx)
frames = [];
if ~isstruct(ctx)
    return;
end
candidatePaths = { ...
    {'frames'}, ...
    {'run','frames'}, ...
    {'selection','frames'}, ...
    {'params','frames'}};
for i = 1:numel(candidatePaths)
    value = nestedValue(ctx, candidatePaths{i});
    if ~isempty(value)
        frames = parseFrames(value);
        if ~isempty(frames)
            return;
        end
    end
end
end

function frameMask = frameMaskFromSelection(frames, sourceFrames)
frameMask = true(numel(sourceFrames), 1);
if isempty(frames)
    return;
end
if islogical(frames)
    frameMask = false(numel(sourceFrames), 1);
    n = min(numel(frames), numel(sourceFrames));
    frameMask(1:n) = frames(1:n);
    return;
end
frames = double(frames(:));
frames = frames(isfinite(frames) & frames >= 1);
if isempty(frames)
    return;
end
frameMask = ismember(sourceFrames, unique(round(frames)));
end

function frames = parseFrames(value)
frames = [];
if isnumeric(value) || islogical(value)
    frames = value;
    return;
end
if iscell(value) && ~isempty(value)
    value = value{end};
end
txt = strtrim(char(string(value)));
if isempty(txt) || any(strcmpi(txt, {'all','*'}))
    return;
end
tokens = regexp(txt, '\d+\s*:\s*\d+|\d+', 'match');
if isempty(tokens)
    return;
end
acc = [];
for i = 1:numel(tokens)
    token = regexprep(tokens{i}, '\s+', '');
    colon = strfind(token, ':');
    if isempty(colon)
        acc(end + 1) = str2double(token); %#ok<AGROW>
    else
        a = str2double(token(1:colon(1)-1));
        b = str2double(token(colon(1)+1:end));
        if isfinite(a) && isfinite(b)
            acc = [acc a:b]; %#ok<AGROW>
        end
    end
end
frames = acc;
end

function root = resolveProjectRoot(ctx)
root = pwd;
if isstruct(ctx)
    for path = {{'projectRoot'}, {'projectDir'}, {'projectPath'}, {'shallow','path'}, {'shallowObj','path'}}
        value = nestedValue(ctx, path{1});
        if ~isempty(value)
            root = char(string(value));
            if exist(root, 'file') == 2
                root = fileparts(root);
            end
            if exist(root, 'dir') == 7
                return;
            end
        end
    end
end
end

function value = nestedValue(s, path)
value = [];
try
    cur = s;
    for i = 1:numel(path)
        key = path{i};
        if isstruct(cur)
            if ~isfield(cur, key)
                return;
            end
            cur = cur.(key);
        elseif isobject(cur)
            if ~isprop(cur, key)
                return;
            end
            cur = cur.(key);
        else
            return;
        end
    end
    value = cur;
catch
    value = [];
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
