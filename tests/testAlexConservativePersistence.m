function tests = testAlexConservativePersistence
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
pluginRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(pluginRoot, 'plugins', 'processor'));
addpath(genpath(fullfile(fileparts(pluginRoot), 'DetecDiv')));
end

function setup(testCase)
testCase.TestData.root = tempname;
mkdir(testCase.TestData.root);
end

function teardown(testCase)
root = testCase.TestData.root;
assert(startsWith(root, tempdir, 'IgnoreCase', true), 'Unexpected test cleanup path.');
rmdir(root, 's');
end

function testAllFramesIgnoresShortRoiCache(testCase)
ctx = struct('frames', 1:20, 'sel', struct('frames', []));
verifyEmpty(testCase, saveCroppedImagesXConservative.selectedFrames(ctx));
ctx.sel.frames = -1;
verifyEqual(testCase, saveCroppedImagesXConservative.selectedFrames(ctx), -1);
end

function testExplicitRunSelectionAndLegacyCaller(testCase)
ctx = struct('frames', 1:20, 'sel', struct('frames', 1:100));
verifyEqual(testCase, saveCroppedImagesXConservative.selectedFrames(ctx), 1:100);
ctx = rmfield(ctx, 'sel');
verifyEqual(testCase, saveCroppedImagesXConservative.selectedFrames(ctx), 1:20);
end

function testHistoricalBlockSizeIsOptionalAndValidated(testCase)
defaults=saveCroppedImagesXConservative.setparam();
verifyEqual(testCase,saveCroppedImagesXConservative.blockSizeArguments(defaults),{'cut',176});
verifyEmpty(testCase,saveCroppedImagesXConservative.blockSizeArguments(struct()));
verifyEqual(testCase,saveCroppedImagesXConservative.blockSizeArguments(struct('cut',256)),{'cut',256});
verifyError(testCase,@() saveCroppedImagesXConservative.blockSizeArguments(struct('cut',0)), ...
    'saveCroppedImagesXConservative:InvalidBlockSize');
verifyError(testCase,@() saveCroppedImagesXConservative.blockSizeArguments(struct('cut',[256 256])), ...
    'saveCroppedImagesXConservative:InvalidBlockSize');
end

function testLegacyResultsRoundTripAndReplacement(testCase)
r = fixtureRoi(testCase);
r.results = expectedResults(1);
verifyTrue(testCase, r.save([], false));
file = xtraFullChannelsConservative.saveResults(r);
verifyTrue(testCase, isfile(file));
fresh = fixtureRoi(testCase); fresh.image = [];
fresh.load('Silent');
verifyEqual(testCase, fresh.results, expectedResults(1));
verifyEqual(testCase, size(fresh.image), [8 8 6 3]);
verifyEmpty(testCase, fresh.data);
fresh.results = expectedResults(2);
xtraFullChannelsConservative.saveResults(fresh);
fresh.results = [];
fresh.load('data');
verifyEqual(testCase, fresh.results, expectedResults(2));
end

function testResultsDoNotChangeUniversalDataSave(testCase)
r = fixtureRoi(testCase);
r.data = dataseries(table((1:3)', 'VariableNames', {'value'}), {'value'}, 'groupid', 'metrics');
verifyTrue(testCase, r.save([], false));
file = fullfile(r.path, ['data_' r.id '.mat']);
before = readBytes(file);
r.results = expectedResults(1);
xtraFullChannelsConservative.saveResults(r);
verifyEqual(testCase, readBytes(file), before);
r.load('data');
verifyEqual(testCase, r.data(1).groupid, 'metrics');
verifyEqual(testCase, r.data(1).data.value, (1:3)');
verifyEqual(testCase, r.results, expectedResults(1));
end

function testMissingSidecarPreservesInMemoryResults(testCase)
r = fixtureRoi(testCase);
verifyTrue(testCase, r.save([], false));
r.results = expectedResults(1);
r.load('Silent');
verifyEqual(testCase, r.results, expectedResults(1));
end

function testDataFalseDoesNotLoadResults(testCase)
r = fixtureRoi(testCase);
verifyTrue(testCase, r.save([], false));
r.results = expectedResults(1);
xtraFullChannelsConservative.saveResults(r);
r.results = expectedResults(2);
r.load('Data', false, 'Silent');
verifyEqual(testCase, r.results, expectedResults(2));
end

function testInvalidResultsAreReported(testCase)
r = fixtureRoi(testCase);
r.results = [];
verifyError(testCase, @() xtraFullChannelsConservative.saveResults(r), ...
    'xtraFullChannelsConservative:ResultsMissing');
results = 42; %#ok<NASGU>
save(fullfile(r.path, ['results_' r.id '.mat']), 'results');
verifyError(testCase, @() r.load('data'), 'loadROI:InvalidLegacyResults');
end

function testSegmentationRerunReplacesLabelsAndKeepsRawChannels(testCase)
r = fixtureRoi(testCase); raw = r.image;
verifyTrue(testCase, r.save([], false));
r.load('Silent');
for label = [2 3]
    labels = uint16(label*ones(8,8,1,3));
    xtraFullChannelsConservative.setSegmentationChannel(r, labels);
    verifyEqual(testCase, r.channelid, 1:7);
    verifyTrue(testCase, r.save({'seg'}, false));
    r.load('Silent');
    verifyEqual(testCase, r.image(:,:,1:6,:), raw);
    verifyEqual(testCase, r.image(:,:,7,:), labels);
end
end

function testExtractionKeepsEarlierBlocksWithOldH5(testCase)
settings = parallel.Settings;
previous = settings.Pool.AutoCreate;
settings.Pool.AutoCreate = false;
poolCleanup = onCleanup(@() restorePoolPreference(previous)); %#ok<NASGU>
root = testCase.TestData.root;
raw = fullfile(root, 'raw'); mkdir(raw);
p = shallow(); p.io = struct('path', [root filesep], 'file', 'project');
f = fov(); f.id = 'position'; f.channel = arrayfun(@(c) sprintf('ch%d', c), 1:6, 'UniformOutput', false);
f.frames = 5*ones(1,6); f.interval = ones(1,6);
f.display.binning = ones(1,6); f.srcpath = repmat({raw}, 1,6);
for c = 1:6
    for t = 1:5
        name = sprintf('c%d_t%d.tif', c,t);
        imwrite(uint16((100*c+t)*ones(16)), fullfile(raw, name));
        entry = dir(fullfile(raw, name));
        f.srclist{c}(t) = entry;
    end
end
r = roi('r1', [2 2 8 8]);
r.path = fullfile(root, 'project', f.id); mkdir(r.path);
r.image = uint16(999*ones(8,8,6,1)); r.channelid = 1:6;
r.display.channel = f.channel;
verifyTrue(testCase, r.save([],false));
f.roi = r; p.fov = f;
saveCroppedImagesXConservative.saveCroppedImages_X(p, 'cut', 2, 'correctdrift', false);
loaded = load(fullfile(r.path, 'im_r1.mat'), 'roiobj');
verifyEqual(testCase, size(loaded.roiobj.image), [8 8 6 5]);
for c = 1:6
    for t = 1:5
        verifyEqual(testCase, loaded.roiobj.image(:,:,c,t), uint16((100*c+t)*ones(8)));
    end
end
end

function r = fixtureRoi(testCase)
r = roi('roundtrip', [1 1 8 8]); r.path = testCase.TestData.root;
r.image = uint16(reshape(1:8*8*6*3, [8 8 6 3])); r.channelid = 1:6;
r.display.channel = arrayfun(@(c) sprintf('ch%d',c), 1:6, 'UniformOutput', false);
end

function results = expectedResults(version)
results = struct('div_1', struct('id', [1 2 version], ...
    'prob', [0.9 NaN 0.2], 'labels', categorical({'unbud', 'small', 'large'})), ...
    'RLS', struct('from_div_1', struct('framediv', [2 3])), ...
    'signal', struct('full', [11 12 13]));
end

function bytes = readBytes(file)
fid = fopen(file, 'rb'); assert(fid >= 0, 'Cannot read test artifact: %s', file);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, '*uint8');
end

function restorePoolPreference(value)
settings = parallel.Settings;
settings.Pool.AutoCreate = value;
end
