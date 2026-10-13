function tests = test_detectViterbiPombeSeptum
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
pluginRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(pluginRoot,'plugins','processor'));
addpath(fullfile(fileparts(pluginRoot),'DetecDiv','structure','classes'));
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
end

function cleanupWorkbook(outputDir)
delete(fullfile(outputDir,'pombe_division_frames.xlsx'));
rmdir(outputDir);
end
