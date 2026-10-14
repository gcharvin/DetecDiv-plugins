function tests = test_detectViterbiPombeSeptum
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
pluginRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(pluginRoot,'plugins','processor'));
addpath(fullfile(fileparts(pluginRoot),'DetecDiv','structure','classes'));
addpath(fullfile(fileparts(pluginRoot),'DetecDiv','structure','io'));
addpath(genpath(fullfile(fileparts(pluginRoot),'DetecDiv','helpers')));
addpath(pluginRoot);
testCase.TestData.pluginRoot=pluginRoot;
testCase.TestData.param = detectViterbiPombeDivisionFrame.setparam();
end

function [raw,mask,xx,yy] = fixture()
[xx,yy] = meshgrid(1:140,1:100);
mask = ((xx-70)/48).^2 + ((yy-50)/19).^2 <= 1;
% Local RNG does not change the application's random-number state.
stream = RandStream('mt19937ar','Seed',42);
raw = 100 + randn(stream,size(xx)) + 0.04*xx;
end

function testStripeDominatesVacuoleAndTexture(testCase)
[raw,mask,xx,yy] = fixture();
stripe = raw - 20*exp(-((xx-70)/1.5).^2);
blob = raw - 25*exp(-((xx-70).^2+(yy-50).^2)/5^2);
[score,pos,info] = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(stripe,mask,testCase.TestData.param);
blobScore = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(blob,mask,testCase.TestData.param);
textureScore = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(raw,mask,testCase.TestData.param);
verifyGreaterThan(testCase,score,1.5);
verifyGreaterThan(testCase,score,5*max([blobScore,textureScore,0.01]));
verifyEqual(testCase,pos,0.5,'AbsTol',0.04);
verifyGreaterThanOrEqual(testCase,info.coverage,0.65);
verifyGreaterThan(testCase,norm(diff(info.lineEndpoints)),20);
end

function testGainOffsetAndRotation(testCase)
[raw,mask,xx] = fixture(); raw = raw - 20*exp(-((xx-70)/1.5).^2);
[score,pos] = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(raw,mask,testCase.TestData.param);
[otherScore,otherPos] = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(3.7*raw+900,mask,testCase.TestData.param);
verifyEqual(testCase,otherScore,score,'RelTol',1e-8);
verifyEqual(testCase,otherPos,pos,'AbsTol',1e-10);
rotated = imrotate(raw,27,'bilinear','crop'); rotatedMask = imrotate(mask,27,'nearest','crop');
[rotatedScore,rotatedPos] = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(rotated,rotatedMask,testCase.TestData.param);
verifyGreaterThan(testCase,rotatedScore,1.5);
verifyEqual(testCase,rotatedPos,0.5,'AbsTol',0.08);
end

function testPolarityAndNoSignal(testCase)
[raw,mask,xx] = fixture(); stripe = raw + 20*exp(-((xx-70)/1.5).^2);
param = testCase.TestData.param; param.septumPolarity = 'bright';
brightScore = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(stripe,mask,param);
param.septumPolarity = 'absolute';
absoluteScore = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(stripe,mask,param);
verifyGreaterThan(testCase,brightScore,1.5);
verifyEqual(testCase,absoluteScore,brightScore,'AbsTol',1e-10);
score = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(100*ones(size(raw)),mask,param);
verifyEqual(testCase,score,0);
[score,pos,info] = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(raw,false(size(mask)),param);
verifyTrue(testCase,isnan(score) && isnan(pos) && all(isnan(info.lineEndpoints),'all'));
end

function testBorderDoesNotBecomeSeptum(testCase)
[raw,mask] = fixture(); raw(~mask) = -500;
score = detectViterbiPombeDivisionFrame.scoreTransverseSeptum(raw,mask,testCase.TestData.param);
verifyLessThan(testCase,score,1.5);
end

function testCoreKeepsLegacyAndExportsLineDiagnostics(testCase)
[raw,mask,xx] = fixture(); raw = raw - 20*exp(-((xx-70)/1.5).^2);
r = roi('synthetic',[]); r.image = cat(3,raw,double(mask));
r.channelid = [1 2]; r.display.channel = {'DIC','instances'};
p = testCase.TestData.param; p.instanceChannelName = 'instances'; p.rawChannelName = 'DIC';
[~,ds] = detectViterbiPombeDivisionFrame.core(p,r,1);
t = ds(strcmp({ds.groupid},p.scoreSeriesName)).data;
verifyTrue(testCase,all(ismember({'septumProfileScore','septumLineCoverage','septumLineX1'},t.Properties.VariableNames)));
verifyTrue(testCase,t.septumDetected(1));
verifyEqual(testCase,ds(end).userData.septumMethod,'transverse2d');
verifyEqual(testCase,ds(end).userData.processorRuntime.pluginVersion,'0.2.1');
p = rmfield(p,'septumMethod');
[~,legacy] = detectViterbiPombeDivisionFrame.core(p,r,1);
p.septumMethod = 'profile';
[~,explicit] = detectViterbiPombeDivisionFrame.core(p,r,1);
verifyEqual(testCase,legacy(end).data,explicit(end).data);
verifyEqual(testCase,width(legacy(end).data),9);
end

function testWorkbookAbstainsWithoutAcceptedLine(testCase)
[raw,mask] = fixture(); r = roi('uncertain',[]);
r.image = cat(3,raw,double(mask)); r.channelid = [1 2]; r.display.channel = {'DIC','instances'};
p = testCase.TestData.param; p.instanceChannelName = 'instances'; p.rawChannelName = 'DIC';
outputDir = tempname; mkdir(outputDir);
cleanup = onCleanup(@() cleanupWorkbook(outputDir)); %#ok<NASGU>
[~,~,~] = detectViterbiPombeDivisionFrame.process(p,r,struct('run',struct('runPath',outputDir)));
t = readtable(fullfile(outputDir,'pombe_division_frames.xlsx'));
verifyTrue(testCase,ismissing(t.DivisionFrame(1)));
verifyTrue(testCase,ismissing(t.SeptumAppearanceFrame(1)));
verifyEqual(testCase,string(t.DetectionStatus(1)),"no_septum_detected");
verifyEqual(testCase,string(t.SeptumMethod(1)),"transverse2d");
verifyEqual(testCase,string(t.PluginVersion(1)),"0.2.1");
verifyTrue(testCase,isfile(fullfile(outputDir,'pombe_septum_mosaic_FOV.png')));
qc=jsondecode(fileread(fullfile(outputDir,'pombe_septum_mosaic_FOV.png.json')));
verifyEqual(testCase,qc.tiles.frame,1);
verifyTrue(testCase,isempty(qc.tiles.appearanceFrame));
end

function testWorkbookSeparatesAppearanceFromPeak(testCase)
[raw,mask,xx] = fixture(); r = roi('growing_septum',[]);
first = cat(3,raw-10*exp(-((xx-70)/1.5).^2),double(mask));
second = cat(3,raw-30*exp(-((xx-70)/1.5).^2),double(mask));
r.image = cat(4,first,second); r.channelid = [1 2]; r.display.channel = {'DIC','instances'};
p = testCase.TestData.param; p.instanceChannelName = 'instances'; p.rawChannelName = 'DIC';
outputDir = tempname; mkdir(outputDir);
cleanup = onCleanup(@() cleanupWorkbook(outputDir)); %#ok<NASGU>
detectViterbiPombeDivisionFrame.process(p,r,struct('run',struct('runPath',outputDir)));
t = readtable(fullfile(outputDir,'pombe_division_frames.xlsx'));
verifyEqual(testCase,t.SeptumAppearanceFrame(1),1);
verifyEqual(testCase,t.SeptumPeakFrame(1),2);
verifyEqual(testCase,t.DivisionFrame(1),2);
qc=jsondecode(fileread(fullfile(outputDir,'pombe_septum_mosaic_FOV.png.json')));
verifyEqual(testCase,qc.tiles.frame,1);
verifyEqual(testCase,qc.tiles.peakFrame,2);
runtime=readtable(fullfile(outputDir,'pombe_division_frames.xlsx'),'Sheet','parameters');
verifyEqual(testCase,string(runtime.EffectiveMethod(1)),"transverse2d");
verifyTrue(testCase,endsWith(string(runtime.CorePath(1)),"core"));
end

function cleanupWorkbook(outputDir)
resolved=char(java.io.File(outputDir).getCanonicalPath());
safeRoot=char(java.io.File(tempdir).getCanonicalPath());
assert(startsWith(resolved,[safeRoot filesep],'IgnoreCase',true));
rmdir(resolved,'s');
end

function testTwoFovsHaveSeparateMosaicsAndPreserveMappings(testCase)
[raw,mask,xx] = fixture();p=testCase.TestData.param;p.instanceChannelName='instances';p.rawChannelName='DIC';
array=cat(3,raw-20*exp(-((xx-70)/1.5).^2),double(mask));
r1=roi('cell1',[]);r1.image=array;r1.channelid=[1 2];r1.display.channel={'DIC','instances'};
r2=roi('cell2',[]);r2.image=array;r2.channelid=[1 2];r2.display.channel={'DIC','instances'};
f1=fov();f1.id='FOV_one';f1.roi=r1;f2=fov();f2.id='FOV_two';f2.roi=r2;
outputDir=tempname;mkdir(outputDir);cleanup=onCleanup(@() cleanupWorkbook(outputDir)); %#ok<NASGU>
ctx=struct('fovList',[f1 f2],'roiList',[r1 r2],'run',struct('runPath',outputDir), ...
    'progress',struct('localBase',0,'localSpan',0.5));
detectViterbiPombeDivisionFrame.process(p,r1,ctx);
before=r1.image;mapping=r1.channelid;display=r1.display;
ctx.progress.localBase=.5;
detectViterbiPombeDivisionFrame.process(p,r2,ctx);
verifyEqual(testCase,r1.image,before);verifyEqual(testCase,r1.channelid,mapping);verifyEqual(testCase,r1.display,display);
verifyTrue(testCase,isfile(fullfile(outputDir,'pombe_septum_mosaic_FOV_one.png')));
verifyTrue(testCase,isfile(fullfile(outputDir,'pombe_septum_mosaic_FOV_two.png')));
end

function testRelinkRemovesBundleBindingAndOldRunOverride(testCase)
outputDir=tempname;mkdir(outputDir);cleanup=onCleanup(@() cleanupWorkbook(outputDir)); %#ok<NASGU>
pipe=pipelineConstruct(outputDir,'template',1);
pipe.nodes=struct('id','septum_1','name','septum_1','type','processor','func','detectViterbiPombeDivisionFrame.process', ...
    'pkg','detectViterbiPombeDivisionFrame','params',struct('septumMethod','profile','anchorX',.42), ...
    'customPackageRoot','C:/old_bundle/processor','customPackageDir','C:/old_bundle/processor/+detectViterbiPombeDivisionFrame');
pipe.runProfiles.main=struct('ctx',struct('run',struct('nodeParams',struct('septum_1',struct('septumMethod','profile')))));
pipelineSave(pipe,'Artifacts',false);
[updated,info]=detecdiv_pombe_septum_relink(pipe.path,testCase.TestData.pluginRoot,'Register',false);
verifyTrue(testCase,isfile(info.backup));
verifyEqual(testCase,updated.nodes.params.septumMethod,'transverse2d');
verifyEqual(testCase,updated.nodes.params.anchorX,.42);
verifyEqual(testCase,updated.runProfiles.main.ctx.run.nodeParams.septum_1.septumMethod,'transverse2d');
verifyTrue(testCase,contains(updated.nodes.customPackageRoot,testCase.TestData.pluginRoot));
end
