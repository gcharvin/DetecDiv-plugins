function paramout = setparam(ctx)
% fociBurstStats.setparam  Parameters for the external foci burst processor.

if nargin < 1 || isempty(ctx)
    ctx = struct();
end

baseDir = defaultOutputRoot(ctx);

paramout = struct();
paramout.outputName = 'foci_burst_stats';
paramout.groupID = '';
paramout.dataIndex = 1;
paramout.framePeriod = 1;
paramout.timeUnit = 'frames';
paramout.nBins = 'auto';
paramout.normalization = 'count';
paramout.xLim = [];
paramout.outputDir = baseDir;
paramout.workbookName = 'foci_burst_stats.xlsx';
paramout.runId = '';
paramout.writeExcel = true;
paramout.writeFigures = false;
paramout.resetRun = false;
paramout.verbose = true;

try
    if isstruct(ctx) && isfield(ctx, 'params') && isstruct(ctx.params)
        paramout = mergeStruct(paramout, ctx.params);
    end
catch
end

paramout.tip = { ...
    'Dataseries groupid written back into each ROI', ...
    'Classification dataseries groupid to read; leave empty to use the first classification dataseries', ...
    'Fallback ROI data index if no classification dataseries is found', ...
    'Time between frames, expressed in timeUnit', ...
    'Time unit label: frames, s, min, or h', ...
    'Histogram bins: auto or a numeric bin count', ...
    'Histogram normalization: count, probability, pdf, cdf, or countdensity', ...
    'Optional histogram x-limits as [xmin xmax]', ...
    'Directory where run state, Excel workbook, and figures are written', ...
    'Excel workbook filename', ...
    'Run id; leave empty to use the pipeline run id when available', ...
    'Write/update the Excel workbook after each processed ROI', ...
    'Save histogram PNG figures after each processed ROI', ...
    'Delete the existing run state before the first ROI of this MATLAB session/run', ...
    'Print progress messages' ...
    };
end

function root = defaultOutputRoot(ctx)
root = projectFolderFromContext(ctx);
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
names = fieldnames(override);
for i = 1:numel(names)
    out.(names{i}) = override.(names{i});
end
end
