function [paramout, dataout, imageout] = core(param, roiobj, ctx)
% fociBurstStats.core  Compute foci burst statistics for one ROI.
%
% This external processor mirrors the logic of computeFociStats.m while
% staying pipeline-compatible. It writes:
%   - one per-ROI dataseries in DetecDiv
%   - one run-level Excel workbook with summary, per-ROI, raw frame, and
%     histogram sheets
%   - optional PNG histogram figures

imageout = [];

if nargin == 0 || isempty(param)
    paramout = fociBurstStats.setparam(struct());
    dataout = [];
    return;
end

if nargin < 3 || isempty(ctx) || ~isstruct(ctx)
    ctx = struct();
end

paramout = normalizeParams(param, ctx);
ensureRunInitialized(paramout);

if isempty(roiobj)
    dataout = [];
    return;
end

if shouldLoadData(roiobj)
    try
        roiobj.load('data', 'Silent');
    catch ME
        warning('fociBurstStats:LoadDataFailed', ...
            'Could not load ROI data before foci stats: %s', ME.message);
    end
end

dataout = roiobj.data;
if isempty(dataout)
    dataout = dataseries;
end

roiKey = makeRoiKey(roiobj);
roiId = makeRoiId(roiobj);
[result, frameTable] = computeOneRoi(roiobj, roiKey, roiId, paramout);

dataout = upsertRoiDataseries(dataout, roiobj, paramout, result, frameTable);

if paramout.writeExcel || paramout.writeFigures
    updateRunArtifacts(paramout, result, frameTable);
end

if paramout.verbose
    fprintf('[fociBurstStats] ROI %s | frames=%d | bouts=%d | workbook=%s\n', ...
        roiId, result.TotalFrames, result.NumBouts, fullfile(paramout.runDir, paramout.workbookName));
end
end

function paramout = normalizeParams(param, ctx)
paramout = param;
if ~isstruct(paramout)
    paramout = struct();
end

defaults = fociBurstStats.setparam(ctx);
paramout = mergeStruct(defaults, paramout);

paramout.outputName = nonemptyChar(paramout.outputName, 'foci_burst_stats');
paramout.groupID = char(string(paramout.groupID));
paramout.dataIndex = max(1, round(numericScalar(paramout.dataIndex, 1)));
paramout.framePeriod = numericScalar(paramout.framePeriod, 1);
if paramout.framePeriod <= 0
    paramout.framePeriod = 1;
end
paramout.timeUnit = validatestring(char(string(paramout.timeUnit)), {'frames','s','min','h'});
paramout.normalization = validatestring(char(string(paramout.normalization)), ...
    {'count','probability','pdf','cdf','countdensity'});
paramout.outputDir = nonemptyChar(paramout.outputDir, defaults.outputDir);
if isempty(paramout.outputDir)
    paramout.outputDir = projectFolderFromContext(ctx);
end
if isempty(paramout.outputDir)
    paramout.outputDir = pwd;
end
paramout.workbookName = nonemptyChar(paramout.workbookName, 'foci_burst_stats.xlsx');
paramout.runId = resolveRunId(paramout, ctx);
paramout.writeExcel = logicalScalar(paramout.writeExcel, true);
paramout.writeFigures = logicalScalar(paramout.writeFigures, false);
paramout.resetRun = logicalScalar(paramout.resetRun, false);
paramout.verbose = logicalScalar(paramout.verbose, true);
paramout.flushArtifacts = shouldFlushArtifacts(ctx);

if isempty(paramout.xLim) || (isnumeric(paramout.xLim) && numel(paramout.xLim) == 2)
    % ok
else
    paramout.xLim = [];
end

safeRunId = matlab.lang.makeValidName(paramout.runId);
paramout.runDir = paramout.outputDir;
if exist(paramout.runDir, 'dir') ~= 7
    mkdir(paramout.runDir);
end
paramout.stateFile = fullfile(paramout.runDir, [safeRunId '_foci_burst_stats_state.mat']);
paramout.initFile = fullfile(paramout.runDir, ['.' safeRunId '_foci_burst_stats_initialized']);
end

function runId = resolveRunId(paramout, ctx)
runId = '';
if isfield(paramout, 'runId') && ~isempty(paramout.runId)
    runId = char(string(paramout.runId));
end
if isempty(runId)
    runId = nestedChar(ctx, {'runId'});
end
if isempty(runId)
    runId = nestedChar(ctx, {'run','runId'});
end
if isempty(runId)
    runId = nestedChar(ctx, {'pipeline','runId'});
end
if isempty(runId)
    runId = 'manual';
end
end

function ensureRunInitialized(paramout)
if ~paramout.resetRun
    return;
end

persistent resetDone
if isempty(resetDone)
    resetDone = containers.Map('KeyType', 'char', 'ValueType', 'logical');
end
resetKey = char(string(paramout.stateFile));
if isKey(resetDone, resetKey)
    return;
end
if exist(paramout.stateFile, 'file') == 2
    delete(paramout.stateFile);
end
workbook = fullfile(paramout.runDir, paramout.workbookName);
if exist(workbook, 'file') == 2
    delete(workbook);
end
resetDone(resetKey) = true;
end

function tf = shouldLoadData(roiobj)
tf = true;
try
    tf = isempty(roiobj.data) || (numel(roiobj.data) == 1 && isempty(roiobj.data(1).data));
catch
end
end

function [result, frameTable] = computeOneRoi(roiobj, roiKey, roiId, opt)
emptyResult = baseResult(roiKey, roiId);
ds = pickClassificationSeries(roiobj, opt.dataIndex, opt.groupID);
if isempty(ds) || ~hasFieldOrProp(ds, 'data') || ~istable(ds.data) || height(ds.data) == 0
    result = emptyResult;
    frameTable = emptyFrameTable(roiKey, roiId);
    result.Status = "missing_classification";
    return;
end

T = normalizeClassifTable(ds.data);
predId = getBinaryID(T);
nFrames = numel(predId);
frame = (1:nFrames)';
time = (frame - 1) .* opt.framePeriod;

[trainId, trainValid] = getTrainingBinary(T);
trainOut = double(trainId(:));
trainOut(~trainValid(:)) = NaN;

frameTable = table( ...
    repmat(string(roiKey), nFrames, 1), ...
    repmat(string(roiId), nFrames, 1), ...
    frame, time, double(predId(:)), trainOut(:), logical(trainValid(:)), ...
    'VariableNames', {'ROIKey','ROIId','Frame','Time','PredFoci','TrainFoci','TrainValid'});

[starts, ends_] = runsOfOnes(predId);
boutLengths = ends_ - starts + 1;
boutDurations = boutLengths(:) .* opt.framePeriod;
interOnset = [];
if numel(starts) >= 2
    starts = starts(:);
    deltas = diff(starts);
    validPairs = starts(1:end-1) > 1;
    interOnset = deltas(validPairs) .* opt.framePeriod;
end

trainEff = uint8(trainId(:) > 0);
trainEff(~trainValid(:)) = 0;
[startsT, endsT] = runsOfOnes(trainEff);
boutDurationsT = (endsT(:) - startsT(:) + 1) .* opt.framePeriod;
interOnsetT = [];
if numel(startsT) >= 2
    startsT = startsT(:);
    deltasT = diff(startsT);
    validPairsT = startsT(1:end-1) > 1;
    interOnsetT = deltasT(validPairsT) .* opt.framePeriod;
end

[hasTrain, nValid, acc, TP, TN, FP, FN] = compareTrainingVsPred(T, predId);

result = emptyResult;
result.Status = "ok";
result.TotalFrames = nFrames;
result.SumFociFrames = sum(predId);
result.HasFoci = any(predId > 0);
result.NumBouts = numel(starts);
if result.HasFoci
    result.OnsetFrame = starts(1);
    result.OnsetTime = (starts(1) - 1) .* opt.framePeriod;
end
result.HasTraining = hasTrain;
result.NTrainValid = nValid;
result.AccTrainVsPred = acc;
result.TP = TP;
result.TN = TN;
result.FP = FP;
result.FN = FN;
result.BoutDurations = boutDurations(:);
result.InterOnsetTimes = interOnset(:);
result.BoutDurationsTrain = boutDurationsT(:);
result.InterOnsetTimesTrain = interOnsetT(:);
end

function result = baseResult(roiKey, roiId)
result = struct();
result.ROIKey = string(roiKey);
result.ROIId = string(roiId);
result.Status = "empty";
result.HasFoci = false;
result.OnsetFrame = NaN;
result.OnsetTime = NaN;
result.NumBouts = 0;
result.SumFociFrames = 0;
result.TotalFrames = 0;
result.HasTraining = false;
result.NTrainValid = 0;
result.AccTrainVsPred = NaN;
result.TP = 0;
result.TN = 0;
result.FP = 0;
result.FN = 0;
result.BoutDurations = [];
result.InterOnsetTimes = [];
result.BoutDurationsTrain = [];
result.InterOnsetTimesTrain = [];
end

function T = emptyFrameTable(roiKey, roiId)
T = table(string.empty(0,1), string.empty(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), false(0,1), ...
    'VariableNames', {'ROIKey','ROIId','Frame','Time','PredFoci','TrainFoci','TrainValid'});
if nargin >= 2
    T.ROIKey = repmat(string(roiKey), 0, 1);
    T.ROIId = repmat(string(roiId), 0, 1);
end
end

function dataout = upsertRoiDataseries(dataout, roiobj, opt, result, frameTable)
if isempty(frameTable)
    frameTable = emptyFrameTable(result.ROIKey, result.ROIId);
end

idx = [];
try
    idx = find(arrayfun(@(x) hasFieldOrProp(x, 'groupid') && strcmp(char(string(x.groupid)), opt.outputName), dataout), 1);
catch
end
if isempty(idx)
    if numel(dataout) == 1 && isempty(dataout(1).data)
        idx = 1;
    else
        idx = numel(dataout) + 1;
    end
end

plotFlags = {false, false, false, false, true, true, false};
groups = {'id','id','frame','time','foci','foci','id'};
ds = dataseries(frameTable, frameTable.Properties.VariableNames, ...
    'groupid', opt.outputName, 'parentid', makeRoiId(roiobj), ...
    'plot', plotFlags, 'groups', groups);
ds.class = "processing";
ds.type = "temporal";
ds.description = 'Foci burst raw 0/1 traces and per-ROI summary.';
ds.userData = struct();
ds.userData.processor = 'fociBurstStats';
ds.userData.summary = resultToSummaryStruct(result);
ds.userData.workbook = fullfile(opt.runDir, opt.workbookName);
ds.userData.runId = opt.runId;
dataout(idx) = ds;
end

function s = resultToSummaryStruct(result)
s = rmfield(result, {'BoutDurations','InterOnsetTimes','BoutDurationsTrain','InterOnsetTimesTrain'});
end

function updateRunArtifacts(opt, result, frameTable)
state = loadState(opt.stateFile);
state = removeRoiFromState(state, result.ROIKey);

ordinal = nextOrdinal(state);
if isfield(state, 'roiOrdinals') && isKey(state.roiOrdinals, char(result.ROIKey))
    ordinal = state.roiOrdinals(char(result.ROIKey));
end
state.roiOrdinals(char(result.ROIKey)) = ordinal;

perRow = resultToPerRoiRow(result, ordinal);
if ~isempty(frameTable)
    frameTable.ROIOrdinal = repmat(ordinal, height(frameTable), 1);
    frameTable = movevars(frameTable, 'ROIOrdinal', 'After', 'ROIId');
end

state.perROI = [state.perROI; perRow];
state.rawFrames = [state.rawFrames; frameTable];
state.distributions = [state.distributions; resultToDistributionRows(result, ordinal)];
state = refreshDistributionVectors(state);
state.updatedAt = char(datetime('now'));
state.options = struct('framePeriod', opt.framePeriod, 'timeUnit', opt.timeUnit, ...
    'normalization', opt.normalization, 'nBins', opt.nBins, 'runId', opt.runId);

save(opt.stateFile, 'state');

if opt.flushArtifacts
    if opt.writeExcel
        writeWorkbook(opt, state);
    end
    if opt.writeFigures
        writeFigures(opt, state);
    end
end
end

function state = loadState(stateFile)
state = struct();
if exist(stateFile, 'file') == 2
    try
        S = load(stateFile, 'state');
        if isfield(S, 'state') && isstruct(S.state)
            state = S.state;
        end
    catch
        state = struct();
    end
end

if ~isfield(state, 'perROI') || ~istable(state.perROI)
    state.perROI = emptyPerRoiTable();
end
if ~isfield(state, 'rawFrames') || ~istable(state.rawFrames)
    state.rawFrames = emptyFrameTable('', '');
    state.rawFrames.ROIOrdinal = zeros(0,1);
    state.rawFrames = movevars(state.rawFrames, 'ROIOrdinal', 'After', 'ROIId');
end
if ~isfield(state, 'boutPred'), state.boutPred = []; end
if ~isfield(state, 'interPred'), state.interPred = []; end
if ~isfield(state, 'boutTrain'), state.boutTrain = []; end
if ~isfield(state, 'interTrain'), state.interTrain = []; end
if ~isfield(state, 'distributions') || ~istable(state.distributions)
    state.distributions = emptyDistributionTable();
end
state = refreshDistributionVectors(state);
if ~isfield(state, 'roiOrdinals') || ~isa(state.roiOrdinals, 'containers.Map')
    state.roiOrdinals = containers.Map('KeyType', 'char', 'ValueType', 'double');
end
end

function state = removeRoiFromState(state, roiKey)
key = string(roiKey);
if istable(state.perROI) && height(state.perROI) > 0
    keep = state.perROI.ROIKey ~= key;
    state.perROI = state.perROI(keep, :);
end
if istable(state.rawFrames) && height(state.rawFrames) > 0
    keep = state.rawFrames.ROIKey ~= key;
    state.rawFrames = state.rawFrames(keep, :);
end
if isfield(state, 'distributions') && istable(state.distributions) && height(state.distributions) > 0
    keep = state.distributions.ROIKey ~= key;
    state.distributions = state.distributions(keep, :);
end
state = refreshDistributionVectors(state);
end

function n = nextOrdinal(state)
n = 1;
try
    if istable(state.perROI) && height(state.perROI) > 0
        n = max(state.perROI.ROIOrdinal) + 1;
    end
catch
end
end

function T = emptyPerRoiTable()
T = table(string.empty(0,1), string.empty(0,1), zeros(0,1), string.empty(0,1), ...
    false(0,1), NaN(0,1), NaN(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    false(0,1), zeros(0,1), NaN(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'ROIKey','ROIId','ROIOrdinal','Status','HasFoci','OnsetFrame','OnsetTime', ...
    'NumBouts','SumFociFrames','TotalFrames','HasTraining','NTrainValid','AccTrainVsPred', ...
    'TP','TN','FP','FN'});
end

function T = resultToPerRoiRow(result, ordinal)
T = table(result.ROIKey, result.ROIId, ordinal, result.Status, logical(result.HasFoci), ...
    result.OnsetFrame, result.OnsetTime, result.NumBouts, result.SumFociFrames, result.TotalFrames, ...
    logical(result.HasTraining), result.NTrainValid, result.AccTrainVsPred, ...
    result.TP, result.TN, result.FP, result.FN, ...
    'VariableNames', {'ROIKey','ROIId','ROIOrdinal','Status','HasFoci','OnsetFrame','OnsetTime', ...
    'NumBouts','SumFociFrames','TotalFrames','HasTraining','NTrainValid','AccTrainVsPred', ...
    'TP','TN','FP','FN'});
end

function T = emptyDistributionTable()
T = table(string.empty(0,1), string.empty(0,1), zeros(0,1), string.empty(0,1), ...
    string.empty(0,1), zeros(0,1), ...
    'VariableNames', {'ROIKey','ROIId','ROIOrdinal','Measure','Source','Value'});
end

function T = resultToDistributionRows(result, ordinal)
T = emptyDistributionTable();
T = [T; distributionRows(result, ordinal, 'bout_duration', 'prediction', result.BoutDurations)];
T = [T; distributionRows(result, ordinal, 'inter_onset', 'prediction', result.InterOnsetTimes)];
T = [T; distributionRows(result, ordinal, 'bout_duration', 'training', result.BoutDurationsTrain)];
T = [T; distributionRows(result, ordinal, 'inter_onset', 'training', result.InterOnsetTimesTrain)];
end

function T = distributionRows(result, ordinal, measure, source, values)
values = values(:);
n = numel(values);
T = table(repmat(result.ROIKey, n, 1), repmat(result.ROIId, n, 1), repmat(ordinal, n, 1), ...
    repmat(string(measure), n, 1), repmat(string(source), n, 1), values, ...
    'VariableNames', {'ROIKey','ROIId','ROIOrdinal','Measure','Source','Value'});
end

function state = refreshDistributionVectors(state)
state.boutPred = [];
state.interPred = [];
state.boutTrain = [];
state.interTrain = [];
if ~isfield(state, 'distributions') || ~istable(state.distributions) || height(state.distributions) == 0
    return;
end
D = state.distributions;
state.boutPred = D.Value(D.Measure == "bout_duration" & D.Source == "prediction");
state.interPred = D.Value(D.Measure == "inter_onset" & D.Source == "prediction");
state.boutTrain = D.Value(D.Measure == "bout_duration" & D.Source == "training");
state.interTrain = D.Value(D.Measure == "inter_onset" & D.Source == "training");
end

function writeWorkbook(opt, state)
workbook = fullfile(opt.runDir, opt.workbookName);
if exist(workbook, 'file') == 2
    delete(workbook);
end

fociByRoi = buildFociByRoiTable(state);
burstIntervals = buildBurstIntervalTable(state);

writetable(fociByRoi, workbook, 'Sheet', 'foci_by_roi');
writetable(burstIntervals, workbook, 'Sheet', 'burst_intervals');
end

function T = buildFociByRoiTable(state)
raw = sortRowsIfPossible(state.rawFrames, {'ROIOrdinal','Frame'});
if isempty(raw) || ~istable(raw) || height(raw) == 0
    T = table(string.empty(0,1), 'VariableNames', {'ROI_id'});
    return;
end

maxFrame = max(raw.Frame);
frameCols = 1:maxFrame;
roiOrdinals = unique(raw.ROIOrdinal, 'stable');
nRois = numel(roiOrdinals);
M = zeros(nRois, maxFrame);
roiIds = strings(nRois, 1);

for i = 1:nRois
    rows = raw(raw.ROIOrdinal == roiOrdinals(i), :);
    rows = sortRowsIfPossible(rows, {'Frame'});
    roiIds(i) = rows.ROIId(1);
    frameIdx = rows.Frame;
    valid = frameIdx >= 1 & frameIdx <= maxFrame;
    M(i, frameIdx(valid)) = double(rows.PredFoci(valid) > 0);
end

varNames = [{'ROI_id'}, arrayfun(@(f)sprintf('F%d', f), frameCols, 'UniformOutput', false)];
data = cell(nRois, numel(varNames));
data(:, 1) = cellstr(roiIds);
data(:, 2:end) = num2cell(M);
T = cell2table(data, 'VariableNames', varNames);
end

function T = buildBurstIntervalTable(state)
[durations, intervals] = burstVectorsFramesFromState(state);
T = table( ...
    string(valuesToCsv(durations)), ...
    string(valuesToCsv(intervals)), ...
    'VariableNames', {'burst_durations_frames','inter_burst_intervals_frames'});
end

function [durations, intervals] = burstVectorsFramesFromState(state)
durations = [];
intervals = [];
raw = sortRowsIfPossible(state.rawFrames, {'ROIOrdinal','Frame'});
if isempty(raw) || ~istable(raw) || height(raw) == 0
    return;
end

roiOrdinals = unique(raw.ROIOrdinal, 'stable');
for i = 1:numel(roiOrdinals)
    rows = raw(raw.ROIOrdinal == roiOrdinals(i), :);
    rows = sortRowsIfPossible(rows, {'Frame'});
    pred = uint8(rows.PredFoci(:) > 0);
    [starts, ends_] = runsOfOnes(pred);
    durations = [durations; (ends_(:) - starts(:) + 1)]; %#ok<AGROW>
    if numel(starts) >= 2
        gaps = starts(2:end) - ends_(1:end-1) - 1;
        intervals = [intervals; gaps(:)]; %#ok<AGROW>
    end
end
end

function txt = valuesToCsv(values)
values = values(:)';
if isempty(values)
    txt = '';
    return;
end
parts = arrayfun(@(x)sprintf('%g', x), values, 'UniformOutput', false);
txt = strjoin(parts, ',');
end

function T = buildSummaryTable(opt, state)
perROI = state.perROI;
nCells = height(perROI);
nWithFoci = sum(perROI.HasFoci);
[boutMed, boutMean, boutStd, boutCv] = quickStats(state.boutPred);
[interMed, interMean, interStd, interCv] = quickStats(state.interPred);
[boutMedT, boutMeanT, boutStdT, boutCvT] = quickStats(state.boutTrain);
[interMedT, interMeanT, interStdT, interCvT] = quickStats(state.interTrain);

TP = sum(perROI.TP);
TN = sum(perROI.TN);
FP = sum(perROI.FP);
FN = sum(perROI.FN);
totalValid = TP + TN + FP + FN;
acc = safeDiv(TP + TN, totalValid);
prec = safeDiv(TP, TP + FP);
rec = safeDiv(TP, TP + FN);
f1 = safeDiv(2 * prec * rec, prec + rec);

metric = string({ ...
    'run_id','updated_at','n_cells','n_cells_with_foci','proportion_with_foci', ...
    'time_unit','frame_period','n_pred_bouts','n_pred_inter_onset','bout_median', ...
    'bout_mean','bout_std','bout_cv','inter_onset_median','inter_onset_mean', ...
    'inter_onset_std','inter_onset_cv','n_train_bouts','n_train_inter_onset', ...
    'bout_median_train','bout_mean_train','bout_std_train','bout_cv_train', ...
    'inter_onset_median_train','inter_onset_mean_train','inter_onset_std_train', ...
    'inter_onset_cv_train','train_total_valid','train_TP','train_TN','train_FP', ...
    'train_FN','train_accuracy','train_precision','train_recall','train_f1'}');
value = { ...
    opt.runId; getFieldDefault(state, 'updatedAt', ''); nCells; nWithFoci; safeDiv(nWithFoci, nCells); ...
    opt.timeUnit; opt.framePeriod; numel(state.boutPred); numel(state.interPred); boutMed; ...
    boutMean; boutStd; boutCv; interMed; interMean; interStd; interCv; ...
    numel(state.boutTrain); numel(state.interTrain); boutMedT; boutMeanT; boutStdT; boutCvT; ...
    interMedT; interMeanT; interStdT; interCvT; totalValid; TP; TN; FP; FN; ...
    acc; prec; rec; f1};
T = table(metric, value, 'VariableNames', {'Metric','Value'});
end

function T = buildHistTable(allValues, predValues, trainValues, opt)
if isempty(allValues)
    T = table(zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
        'VariableNames', {'Bin','LeftEdge','RightEdge','Center','Pred','Train'});
    return;
end

if ischar(opt.nBins) || isstring(opt.nBins)
    if strcmpi(char(string(opt.nBins)), 'auto')
        [~, edges] = histcounts(allValues, 'BinMethod', 'auto');
    else
        nBins = str2double(char(string(opt.nBins)));
        [~, edges] = histcounts(allValues, 'NumBins', max(1, round(nBins)));
    end
else
    [~, edges] = histcounts(allValues, 'NumBins', max(1, round(double(opt.nBins))));
end
pred = histcounts(predValues, edges, 'Normalization', opt.normalization);
train = histcounts(trainValues, edges, 'Normalization', opt.normalization);
left = edges(1:end-1)';
right = edges(2:end)';
center = (left + right) ./ 2;
T = table((1:numel(pred))', left, right, center, pred(:), train(:), ...
    'VariableNames', {'Bin','LeftEdge','RightEdge','Center','Pred','Train'});
end

function writeFigures(opt, state)
writeOneFigure(fullfile(opt.runDir, 'hist_bout.png'), state.boutPred, state.boutTrain, ...
    'Foci burst durations', ['Duration (' opt.timeUnit ')'], opt);
writeOneFigure(fullfile(opt.runDir, 'hist_inter_onset.png'), state.interPred, state.interTrain, ...
    'Foci inter-onset intervals', ['Interval (' opt.timeUnit ')'], opt);
end

function writeOneFigure(filePath, predValues, trainValues, titleText, xLabelText, opt)
allValues = [predValues(:); trainValues(:)];
if isempty(allValues)
    return;
end
if ischar(opt.nBins) || isstring(opt.nBins)
    if strcmpi(char(string(opt.nBins)), 'auto')
        [~, edges] = histcounts(allValues, 'BinMethod', 'auto');
    else
        [~, edges] = histcounts(allValues, 'NumBins', max(1, round(str2double(char(string(opt.nBins))))));
    end
else
    [~, edges] = histcounts(allValues, 'NumBins', max(1, round(double(opt.nBins))));
end

fig = figure('Visible', 'off', 'Color', 'w', 'Name', titleText);
cleanup = onCleanup(@() close(fig));
hold on;
if ~isempty(predValues)
    histogram(predValues, 'BinEdges', edges, 'Normalization', opt.normalization, ...
        'FaceColor', [0.85 0.2 0.2], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
end
if ~isempty(trainValues)
    histogram(trainValues, 'BinEdges', edges, 'Normalization', opt.normalization, ...
        'FaceColor', [0.2 0.4 0.9], 'EdgeColor', 'none', 'FaceAlpha', 0.5);
end
xlabel(xLabelText);
ylabel(localYLabel(opt.normalization));
title(titleText);
if ~isempty(opt.xLim)
    xlim(opt.xLim);
end
grid on;
if ~isempty(predValues) && ~isempty(trainValues)
    legend({'prediction','training'}, 'Location', 'best');
elseif ~isempty(predValues)
    legend({'prediction'}, 'Location', 'best');
elseif ~isempty(trainValues)
    legend({'training'}, 'Location', 'best');
end
hold off;
saveas(fig, filePath);
end

function ds = pickClassificationSeries(roiobj, dataIndex, groupID)
ds = [];
if ~hasFieldOrProp(roiobj, 'data') || isempty(roiobj.data)
    return;
end

if strlength(string(groupID)) > 0
    for ii = 1:numel(roiobj.data)
        cur = roiobj.data(ii);
        if hasFieldOrProp(cur, 'class') && strcmp(string(cur.class), "classification")
            if hasFieldOrProp(cur, 'groupid') && strcmp(string(cur.groupid), string(groupID))
                ds = cur;
                return;
            end
        end
    end
end

for ii = 1:numel(roiobj.data)
    cur = roiobj.data(ii);
    if hasFieldOrProp(cur, 'class') && strcmp(string(cur.class), "classification")
        ds = cur;
        return;
    end
end

if isempty(ds) && dataIndex <= numel(roiobj.data)
    cur = roiobj.data(dataIndex);
    if hasFieldOrProp(cur, 'data') && istable(cur.data)
        ds = cur;
    end
end
end

function T = normalizeClassifTable(Tin)
if ~istable(Tin)
    error('fociBurstStats:InputNotTable', 'Classification data must be a table.');
end
T = Tin;
n = height(T);
vars = string(T.Properties.VariableNames);

if ~ismember("id", vars)
    T.id = zeros(n, 1, 'uint8');
end
if ~ismember("labels", string(T.Properties.VariableNames))
    if ismember("prob_foci", string(T.Properties.VariableNames))
        T.labels = strings(n, 1);
        T.labels(T.prob_foci >= 0.5) = "foci";
        T.labels(T.prob_foci < 0.5) = "nofoci";
    else
        T.labels = strings(n, 1);
        T.labels(T.id > 0) = "foci";
        T.labels(T.id <= 0) = "nofoci";
    end
end
if ~ismember("prob_foci", string(T.Properties.VariableNames))
    T.prob_foci = double(uint8(T.id) > 0);
end
if ~ismember("prob_nofoci", string(T.Properties.VariableNames))
    T.prob_nofoci = 1 - double(T.prob_foci);
end
if ~ismember("id_training", string(T.Properties.VariableNames))
    T.id_training = NaN(n, 1);
end
if ~ismember("labels_training", string(T.Properties.VariableNames))
    T.labels_training = repmat("unlabeled", n, 1);
end

T.id = uint8(T.id);
T.labels = string(T.labels);
T.labels_training = string(T.labels_training);
end

function id = getBinaryID(T)
if ismember("labels", string(T.Properties.VariableNames))
    id = uint8(strcmpi(string(T.labels), "foci"));
elseif ismember("prob_foci", string(T.Properties.VariableNames))
    id = uint8(T.prob_foci >= 0.5);
elseif ismember("id", string(T.Properties.VariableNames)) && any(~isnan(double(T.id)))
    id = uint8(T.id > 0);
else
    error('fociBurstStats:NoPrediction', 'Could not infer foci prediction.');
end
id = uint8(id(:) > 0);
end

function [trainId, validMask] = getTrainingBinary(T)
n = height(T);
trainId = zeros(n, 1, 'uint8');
validMask = false(n, 1);

if ismember("labels_training", string(T.Properties.VariableNames))
    lbl = string(T.labels_training);
    isFoci = strcmpi(lbl, "foci");
    isNoFoci = strcmpi(lbl, "nofoci");
    valid = isFoci | isNoFoci;
    trainId(valid) = uint8(isFoci(valid));
    validMask = validMask | valid;
end

if ismember("id_training", string(T.Properties.VariableNames))
    idtr = double(T.id_training);
    use = ~validMask & ~isnan(idtr);
    trainId(use) = uint8(idtr(use) > 0);
    validMask = validMask | use;
end
end

function [hasTrain, nValid, acc, TP, TN, FP, FN] = compareTrainingVsPred(T, predId)
[trainId, validMask] = getTrainingBinary(T);
hasTrain = any(validMask);
if ~hasTrain
    nValid = 0;
    acc = NaN;
    TP = 0; TN = 0; FP = 0; FN = 0;
    return;
end
pred = uint8(predId(:) > 0);
train = uint8(trainId(:) > 0);
pred = pred(validMask);
train = train(validMask);
nValid = numel(train);
TP = sum(pred == 1 & train == 1);
TN = sum(pred == 0 & train == 0);
FP = sum(pred == 1 & train == 0);
FN = sum(pred == 0 & train == 1);
acc = safeDiv(TP + TN, nValid);
end

function [starts, ends_] = runsOfOnes(id)
id = id(:) > 0;
d = diff([false; id; false]);
starts = find(d == 1);
ends_ = find(d == -1) - 1;
end

function [med, m, s, cv] = quickStats(v)
if isempty(v)
    med = NaN; m = NaN; s = NaN; cv = NaN;
    return;
end
v = v(:);
med = median(v, 'omitnan');
m = mean(v, 'omitnan');
s = std(v, 'omitnan');
cv = safeDiv(s, m);
end

function ylab = localYLabel(normstr)
switch lower(char(string(normstr)))
    case 'count'
        ylab = 'Count';
    case 'probability'
        ylab = 'Probability';
    case 'pdf'
        ylab = 'PDF';
    case 'cdf'
        ylab = 'CDF';
    case 'countdensity'
        ylab = 'Count density';
    otherwise
        ylab = 'Count';
end
end

function out = sortRowsIfPossible(T, keys)
out = T;
try
    out = sortrows(T, keys);
catch
end
end

function val = safeDiv(a, b)
if b == 0 || isnan(b)
    val = NaN;
else
    val = a ./ b;
end
end

function out = mergeStruct(base, override)
out = base;
names = fieldnames(override);
for i = 1:numel(names)
    out.(names{i}) = override.(names{i});
end
end

function tf = hasFieldOrProp(obj, name)
tf = false;
try
    if isstruct(obj)
        tf = isfield(obj, name);
    else
        tf = isprop(obj, name);
    end
catch
end
end

function out = nestedChar(S, pathParts)
out = '';
try
    cur = S;
    for i = 1:numel(pathParts)
        if ~isstruct(cur) || ~isfield(cur, pathParts{i})
            return;
        end
        cur = cur.(pathParts{i});
    end
    if ~isempty(cur)
        out = char(string(cur));
    end
catch
    out = '';
end
end

function root = projectFolderFromContext(ctx)
root = '';
if nargin < 1 || isempty(ctx) || ~isstruct(ctx)
    return;
end
pathValue = nestedChar(ctx, {'projectPath'});
if isempty(pathValue), pathValue = nestedChar(ctx, {'run','projectPath'}); end
if isempty(pathValue), pathValue = nestedChar(ctx, {'io','projectPath'}); end
if isempty(pathValue), pathValue = nestedChar(ctx, {'targetRef','projectPath'}); end
root = projectFolderFromPath(pathValue);
if ~isempty(root)
    return;
end
try
    shallowObj = [];
    if isfield(ctx, 'shallow') && isa(ctx.shallow, 'shallow')
        shallowObj = ctx.shallow;
    elseif isfield(ctx, 'shallowObj') && isa(ctx.shallowObj, 'shallow')
        shallowObj = ctx.shallowObj;
    end
    if ~isempty(shallowObj)
        [pth, name] = shallowObj.getPath;
        root = fullfile(pth, name);
    end
catch
    root = '';
end
end

function root = projectFolderFromPath(pathValue)
root = '';
if isempty(pathValue)
    return;
end
pathValue = char(string(pathValue));
if exist(pathValue, 'dir') == 7
    root = pathValue;
    return;
end
[pth, name, ext] = fileparts(pathValue);
if strcmpi(ext, '.mat')
    candidate = fullfile(pth, name);
    if exist(candidate, 'dir') == 7
        root = candidate;
    elseif ~isempty(pth)
        root = pth;
    end
elseif ~isempty(pth)
    root = pth;
end
end

function out = nonemptyChar(value, defaultValue)
out = char(string(defaultValue));
try
    if ~isempty(value) && strlength(string(value)) > 0
        out = char(string(value));
    end
catch
end
end

function out = numericScalar(value, defaultValue)
out = defaultValue;
try
    if iscell(value)
        value = value{end};
    end
    out = double(value);
catch
    out = defaultValue;
end
if isempty(out) || ~isscalar(out) || ~isfinite(out)
    out = defaultValue;
end
end

function out = logicalScalar(value, defaultValue)
out = defaultValue;
try
    if iscell(value)
        value = value{end};
    end
    out = logical(value);
catch
    out = defaultValue;
end
if isempty(out) || ~isscalar(out)
    out = defaultValue;
end
end

function tf = shouldFlushArtifacts(ctx)
tf = true;
try
    if ~isstruct(ctx) || ~isfield(ctx, 'progress') || ~isstruct(ctx.progress)
        return;
    end
    if isfield(ctx.progress, 'roiIndex') && isfield(ctx.progress, 'totalRois') && ...
            ~isempty(ctx.progress.roiIndex) && ~isempty(ctx.progress.totalRois)
        tf = double(ctx.progress.roiIndex) >= double(ctx.progress.totalRois);
    end
catch
    tf = true;
end
end

function roiId = makeRoiId(roiobj)
roiId = '';
try
    if hasFieldOrProp(roiobj, 'id') && ~isempty(roiobj.id)
        roiId = char(string(roiobj.id));
    end
catch
end
if isempty(roiId)
    roiId = 'roi';
end
end

function roiKey = makeRoiKey(roiobj)
roiId = makeRoiId(roiobj);
pathText = '';
try
    if hasFieldOrProp(roiobj, 'path') && ~isempty(roiobj.path)
        pathText = char(string(roiobj.path));
    end
catch
end
roiKey = char(string(matlab.lang.makeValidName([roiId '_' char(string(DataHashLocal(pathText))) ])));
end

function h = DataHashLocal(txt)
% Small deterministic hash for ROI key disambiguation without dependencies.
txt = char(string(txt));
v = uint32(2166136261);
for i = 1:numel(txt)
    v = bitxor(v, uint32(txt(i)));
    v = uint32(mod(uint64(v) * uint64(16777619), uint64(2)^32));
end
h = dec2hex(v, 8);
end

function val = getFieldDefault(S, field, defaultValue)
val = defaultValue;
try
    if isstruct(S) && isfield(S, field)
        val = S.(field);
    end
catch
end
end
