function [stats, perROI, rawFrames] = runOnRois(roiList, varargin)
% fociBurstStats.runOnRois  Convenience entry point outside pipeline2.
%
% Example:
%   load_fociBurstStats_plugin
%   [stats, perROI, raw] = fociBurstStats.runOnRois(shallowObj.fov(1).roi, ...
%       'groupID', 'cnnlstm_2', 'framePeriod', 1, 'timeUnit', 'min');

p = inputParser;
addParameter(p, 'groupID', '');
addParameter(p, 'dataIndex', 1);
addParameter(p, 'framePeriod', 1);
addParameter(p, 'timeUnit', 'frames');
addParameter(p, 'nBins', 'auto');
addParameter(p, 'normalization', 'count');
addParameter(p, 'outputName', 'foci_burst_stats');
addParameter(p, 'outputDir', '');
addParameter(p, 'workbookName', 'foci_burst_stats.xlsx');
addParameter(p, 'runId', ['manual_' datestr(now, 'yyyymmdd_HHMMSS')]);
addParameter(p, 'writeExcel', true);
addParameter(p, 'writeFigures', true);
parse(p, varargin{:});

ctx = struct();
param = fociBurstStats.setparam(ctx);
names = fieldnames(p.Results);
for i = 1:numel(names)
    param.(names{i}) = p.Results.(names{i});
end
param.resetRun = true;

for i = 1:numel(roiList)
    fociBurstStats.process(param, roiList(i), ctx);
end

param = fociBurstStats.setparam(struct('params', param));
param.runId = p.Results.runId;
param = fociBurstStats.core(param, [], ctx);

stateFile = fullfile(p.Results.outputDir, [matlab.lang.makeValidName(p.Results.runId) '_foci_burst_stats_state.mat']);
if isempty(p.Results.outputDir)
    defaultParam = fociBurstStats.setparam();
    stateFile = fullfile(defaultParam.outputDir, [matlab.lang.makeValidName(p.Results.runId) '_foci_burst_stats_state.mat']);
end
S = load(stateFile, 'state');
perROI = S.state.perROI;
rawFrames = S.state.rawFrames;
stats = S.state;
end
