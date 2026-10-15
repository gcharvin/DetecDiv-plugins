function tests = testAlexPipelineChannels
tests = functiontests(localfunctions);
end

function setupOnce(~)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(fileparts(root),'DetecDiv')));
addpath(fullfile(root,'plugins','processor'));
end

function testRawChannelsReachClassificationBeforeExtraction(t)
[pipe,ctx] = fixture(6);
[ok,report] = validatePipeline(pipe,ctx,struct('allowGui',false));
verifyTrue(t,ok,strjoin(report.errors,' | '));
verifyTrue(t,all(ismember(ctx.channels,report.semantic.analysis.availableChannels)));
outputs = report.binding.nodes.extract.resources.outputs;
verifyTrue(t,all(ismember(ctx.channels,{outputs.concreteName})));
verifyTrue(t,all(strcmp({outputs.sourceKind},'imagesToRoi')));
end

function testClassificationAloneStillRejectsUnextractedRois(t)
[pipe,ctx] = fixture(6);
pipe.nodes = pipe.nodes(2); pipe.edges = struct([]);
[ok,report] = validatePipeline(pipe,ctx,struct('allowGui',false));
verifyFalse(t,ok);
verifyTrue(t,any(contains(report.errors,'expects at least 6 channel(s)')));
end

function testFiveRawChannelsCannotSatisfySixChannelAnalysis(t)
[pipe,ctx] = fixture(5);
ctx.roiChannels = {};
[ok,report] = validatePipeline(pipe,ctx,struct('allowGui',false));
verifyFalse(t,ok);
verifyTrue(t,any(contains(report.errors,'expects at least 6 channel(s)')));
end

function testExistingSixChannelResultsNeedNoExtraction(t)
[pipe,ctx] = fixture(6);
pipe.nodes = pipe.nodes(2); pipe.edges = struct([]);
ctx.roiChannels = ctx.channels;
[ok,report] = validatePipeline(pipe,ctx,struct('allowGui',false));
verifyTrue(t,ok,strjoin(report.errors,' | '));
end

function [pipe,ctx] = fixture(count)
names = {'channel000_z000','channel000_z001','channel000_z002', ...
    'channel001_z001','channel002_z001','channel003_z001'};
a = node('extract','saveCroppedImagesXConservative');
b = node('analysis','xtraFullChannelsConservative');
pipe = struct('nodes',[a b],'edges',struct('from','extract','to','analysis', ...
    'fromPort','roiList','toPort','roiList','condition',''));
ctx = struct('images',1,'roiList',1,'channels',{names(1:count)}, ...
    'roiChannels',{{'Channel 1'}},'run',struct('inputSourceMode','existing_rois'));
end

function n = node(id,pkg)
n = struct('id',id,'type','processor','pkg',pkg,'func',[pkg '.process'], ...
    'params',struct('pkg',pkg),'enabled',true);
end
