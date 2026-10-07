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

% Export once, after the last ROI in the processor batch has received its
% score dataseries. The exported division frame uses the default downstream
% selection rule: the frame with the maximum finite score on a valid track.
if shouldExportDivisionFrameWorkbook(roiobj, ctx)
    paramout.divisionFramesWorkbookPath = writeDivisionFrameWorkbook( ...
        ctx, roiobj, paramout.scoreSeriesName);
end
end

function tf = shouldExportDivisionFrameWorkbook(roiobj, ctx)
tf = true;
try
    if isfield(ctx, 'progress') && isstruct(ctx.progress) && ...
            isfield(ctx.progress, 'localBase') && isfield(ctx.progress, 'localSpan')
        tf = double(ctx.progress.localBase) + double(ctx.progress.localSpan) >= 1 - 1e-9;
        return;
    end
catch
end

try
    if isfield(ctx, 'roiList') && ~isempty(ctx.roiList)
        currentId = char(string(roiobj.id));
        lastId = char(string(ctx.roiList(end).id));
        tf = strcmp(currentId, lastId);
    end
catch
end
end

function workbookPath = writeDivisionFrameWorkbook(ctx, currentRoi, scoreSeriesName)
fovList = [];
try
    if isfield(ctx, 'fovList') && ~isempty(ctx.fovList)
        fovList = ctx.fovList;
    end
catch
end
if isempty(fovList)
    project = [];
    try
        if isfield(ctx, 'shallow') && isa(ctx.shallow, 'shallow')
            project = ctx.shallow;
        elseif isfield(ctx, 'shallowObj') && isa(ctx.shallowObj, 'shallow')
            project = ctx.shallowObj;
        end
        if ~isempty(project), fovList = project.fov; end
    catch
    end
end

roiList = currentRoi;
try
    if isfield(ctx, 'roiList') && ~isempty(ctx.roiList)
        roiList = ctx.roiList;
    end
catch
end

groups = struct('id', {}, 'rois', {});
for i = 1:numel(fovList)
    try
        fovId = char(string(fovList(i).id));
        fovRois = fovList(i).roi;
    catch
        continue;
    end
    selected = false(1, numel(roiList));
    fovRoiIds = cell(1, numel(fovRois));
    for j = 1:numel(fovRois)
        try, fovRoiIds{j} = char(string(fovRois(j).id)); catch, end
    end
    for j = 1:numel(roiList)
        selected(j) = any(strcmp(char(string(roiList(j).id)), fovRoiIds));
        if ~selected(j)
            try
                selected(j) = strcmp(char(string(roiList(j).parent.id)), fovId);
            catch
            end
        end
    end
    groups(end+1) = struct('id', fovId, 'rois', roiList(selected)); %#ok<AGROW>
end

if isempty(groups)
    groups = struct('id', 'FOV', 'rois', roiList);
end

outputDir = divisionFrameOutputDir(ctx, currentRoi);
if exist(outputDir, 'dir') ~= 7
    mkdir(outputDir);
end
workbookPath = fullfile(outputDir, 'pombe_division_frames.xlsx');
if exist(workbookPath, 'file') == 2
    delete(workbookPath);
end

usedSheets = {};
for i = 1:numel(groups)
    sheetName = uniqueSheetName(groups(i).id, usedSheets);
    usedSheets{end+1} = sheetName; %#ok<AGROW>
    rows = groups(i).rois;
    roiIds = strings(numel(rows), 1);
    divisionFrames = nan(numel(rows), 1);
    for j = 1:numel(rows)
        roiIds(j) = string(rows(j).id);
        divisionFrames(j) = maxValidScoreFrame(rows(j), scoreSeriesName);
    end
    outputTable = table(roiIds, divisionFrames, ...
        'VariableNames', {'ROI', 'DivisionFrame'});
    writetable(outputTable, workbookPath, 'Sheet', sheetName);
end
end

function outputDir = divisionFrameOutputDir(ctx, roiobj)
outputDir = '';
try
    if isfield(ctx, 'run') && isstruct(ctx.run)
        if isfield(ctx.run, 'runPath') && ~isempty(ctx.run.runPath)
            outputDir = char(string(ctx.run.runPath));
        elseif isfield(ctx.run, 'path') && ~isempty(ctx.run.path)
            outputDir = char(string(ctx.run.path));
        end
    end
catch
end
if isempty(outputDir)
    try
        if isfield(ctx, 'store') && isstruct(ctx.store) && ...
                isfield(ctx.store, 'runPath') && ~isempty(ctx.store.runPath)
            outputDir = char(string(ctx.store.runPath));
        end
    catch
    end
end
if isempty(outputDir)
    projectPath = '';
    try
        if isfield(ctx, 'io') && isstruct(ctx.io) && ...
                isfield(ctx.io, 'projectPath') && ~isempty(ctx.io.projectPath)
            projectPath = char(string(ctx.io.projectPath));
        elseif isfield(ctx, 'projectPath') && ~isempty(ctx.projectPath)
            projectPath = char(string(ctx.projectPath));
        elseif isfield(ctx, 'shallow') && isa(ctx.shallow, 'shallow')
            projectPath = char(string(ctx.shallow.io.path));
        elseif isfield(ctx, 'shallowObj') && isa(ctx.shallowObj, 'shallow')
            projectPath = char(string(ctx.shallowObj.io.path));
        end
    catch
    end
    if ~isempty(projectPath)
        if exist(projectPath, 'dir') == 7
            outputDir = projectPath;
        else
            outputDir = fileparts(projectPath);
        end
    end
end
if isempty(outputDir)
    try
        outputDir = fileparts(char(string(roiobj.path)));
    catch
    end
end
if isempty(outputDir), outputDir = pwd; end
end

function sheetName = uniqueSheetName(fovId, usedSheets)
base = regexprep(char(string(fovId)), '[\[\]:*?/\\]', '_');
if isempty(strtrim(base)), base = 'FOV'; end
base = base(1:min(31, numel(base)));
sheetName = base;
suffix = 1;
while any(strcmpi(sheetName, usedSheets))
    suffix = suffix + 1;
    suffixText = sprintf('_%d', suffix);
    prefix = base(1:min(numel(base), 31 - numel(suffixText)));
    sheetName = [prefix suffixText]; %#ok<AGROW>
end
end

function frame = maxValidScoreFrame(roiobj, scoreSeriesName)
frame = NaN;
try
    data = roiobj.data;
    if ~hasScoreSeries(data, scoreSeriesName)
        % processData may clear ROI dataseries from memory after saving them.
        % Reload prior ROIs so the final workbook still includes their results.
        roiobj.load('data');
        data = roiobj.data;
    end
    for i = 1:numel(data)
        if ~strcmp(char(string(data(i).groupid)), char(string(scoreSeriesName)))
            continue;
        end
        tbl = data(i).data;
        if ~istable(tbl) || height(tbl) == 0 || ...
                ~ismember('septumScore', tbl.Properties.VariableNames)
            return;
        end
        scores = double(tbl.septumScore(:));
        if ismember('trackValid', tbl.Properties.VariableNames)
            validTrack = logical(tbl.trackValid(:));
        else
            validTrack = true(size(scores));
        end
        valid = isfinite(scores) & validTrack;
        if any(valid)
            frames = double(tbl.frame(:));
            validIdx = find(valid);
            [~, bestIdx] = max(scores(valid));
            frame = frames(validIdx(bestIdx));
        end
        return;
    end
catch
end
end

function tf = hasScoreSeries(data, scoreSeriesName)
tf = false;
try
    for i = 1:numel(data)
        if strcmp(char(string(data(i).groupid)), char(string(scoreSeriesName)))
            tf = true;
            return;
        end
    end
catch
end
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
