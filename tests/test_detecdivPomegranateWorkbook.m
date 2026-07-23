function tests = test_detecdivPomegranateWorkbook
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
pluginRoot = fileparts(fileparts(mfilename('fullpath')));
matlabRoot = fileparts(pluginRoot);
detecdivRoot = fullfile(matlabRoot, 'DetecDiv');
addpath(fullfile(pluginRoot, 'plugins', 'processor'));
addpath(fullfile(detecdivRoot, 'structure', 'classes'));
testCase.TestData.pluginRoot = pluginRoot;
end

function testWorkbookContainsSummaryParametersAndTailNamedRoiSheets(testCase)
outputDir = tempname;
mkdir(outputDir);
cleanup = onCleanup(@() removeTestDirectory(outputDir)); %#ok<NASGU>

workbookName = 'pomegranate_test.xlsx';
ids = { ...
    'experiment_with_a_long_shared_prefix_position_0001_roi_0042', ...
    'experiment_with_a_long_shared_prefix_position_0001_roi_0043'};

for i = 1:numel(ids)
    runOneRoi(ids{i}, outputDir, workbookName);
end
% A rerun must replace the ROI rows, not append duplicates.
runOneRoi(ids{1}, outputDir, workbookName);

workbookPath = fullfile(outputDir, workbookName);
names = cellstr(string(sheetnames(workbookPath)));
verifyTrue(testCase, any(strcmp(names, 'summary')));
verifyTrue(testCase, any(strcmp(names, 'parameters')));

expectedDetailNames = cellfun(@tailSheetName, ids, 'UniformOutput', false);
for i = 1:numel(expectedDetailNames)
    verifyTrue(testCase, any(strcmp(names, expectedDetailNames{i})));
    detail = readtable(workbookPath, 'Sheet', expectedDetailNames{i});
    verifyEqual(testCase, height(detail), 5);
end

summary = readtable(workbookPath, 'Sheet', 'summary', 'VariableNamingRule', 'preserve');
parameters = readtable(workbookPath, 'Sheet', 'parameters', 'VariableNamingRule', 'preserve');
verifyEqual(testCase, height(summary), 2);
verifyEqual(testCase, height(parameters), 2);
verifyEqual(testCase, sort(string(summary.roiId)), sort(string(ids(:))));
verifyGreaterThan(testCase, min(summary.volume_voxels), 0);
verifyGreaterThan(testCase, min(summary.volume_um3), 0);
verifyEqual(testCase, sort(string(summary.detailSheet)), sort(string(expectedDetailNames(:))));
end

function runOneRoi(id, outputDir, workbookName)
zNames = arrayfun(@(z) sprintf('DIC_Z%03d', z), 1:5, 'UniformOutput', false);
obj = roi(id, [1 1 32 32]);
obj.path = outputDir;
obj.display.channel = [zNames, {'cell_of_interest'}];
obj.channelid = 1:6;
obj.image = zeros(32, 32, 6, 1, 'uint16');
[xx, yy] = meshgrid(1:32, 1:32);
mask = ((xx - 16).^2 / 8^2 + (yy - 16).^2 / 4^2) <= 1;
for z = 1:5
    obj.image(:, :, z, 1) = uint16(100 * z + xx + yy);
end
obj.image(:, :, 6, 1) = uint16(mask);

param = detecdivPomegranate.setparam();
param.zStackChannelNames = zNames;
param.cellMaskChannelName = 'cell_of_interest';
param.frameSelectionMode = 'manual_frame';
param.manualFrame = 1;
param.outputDir = outputDir;
param.resultsWorkbookName = workbookName;
param.writeCsv = false;
param.writeExcel = true;
param.writeQcImages = false;
param.writeMosaicImage = false;
detecdivPomegranate.process(param, obj, struct());
end

function name = tailSheetName(raw)
name = regexprep(char(string(raw)), '[:\\/?*\[\]]', '_');
name = strtrim(name);
name = name(max(1, numel(name) - 30):end);
end

function removeTestDirectory(path)
if exist(path, 'dir') == 7
    rmdir(path, 's');
end
end
