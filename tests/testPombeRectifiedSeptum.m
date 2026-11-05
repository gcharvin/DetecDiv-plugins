function tests=testPombeRectifiedSeptum
tests=functiontests(localfunctions);
end

function setupOnce(~)
root=fileparts(fileparts(mfilename('fullpath')));addpath(fullfile(root,'plugins','processor'));
end

function [raw,mask,x,y]=fixture(curved)
[x,y]=meshgrid(1:140,1:110);mid=55+curved*.007*(x-70).^2;
mask=((x-70)/48).^2+((y-mid)/18).^2<=1;
rngLocal=RandStream('mt19937ar','Seed',31);
raw=100+.03*x+randn(rngLocal,size(x));
end

function testStraightStripeAndGranule(testCase)
[raw,mask,x,y]=fixture(false);
[score,pos,info]=detectViterbiPombeDivisionFrame.scoreRectifiedSeptum(raw-20*exp(-((x-70)/1.5).^2),mask);
blob=detectViterbiPombeDivisionFrame.scoreRectifiedSeptum(raw-25*exp(-((x-70).^2+(y-55).^2)/25),mask);
verifyGreaterThan(testCase,score,1.5);verifyLessThan(testCase,blob,1.5);
verifyEqual(testCase,pos,.5,'AbsTol',.06);verifyGreaterThanOrEqual(testCase,info.coverage,.8);
verifyNotEmpty(testCase,info.rectified);verifyTrue(testCase,all(isfinite(info.lineEndpoints),'all'));
end

function testCurvedAxisAndPhotometricInvariance(testCase)
[raw,mask,x]=fixture(true);raw=raw-20*exp(-((x-70)/1.5).^2);
[score,pos,info]=detectViterbiPombeDivisionFrame.scoreRectifiedSeptum(raw,mask);
[other,p]=detectViterbiPombeDivisionFrame.scoreRectifiedSeptum(4*raw+9000,mask);
verifyGreaterThan(testCase,score,1.5);verifyEqual(testCase,score,other,'RelTol',1e-8);
verifyEqual(testCase,pos,p,'AbsTol',1e-8);verifyEqual(testCase,info.axisMode,'curved_axis');
verifyGreaterThan(testCase,range(info.centerline(:,2)),2);
end

function testRoundCellUsesImageOrientationSearch(testCase)
[raw,~,x,y]=fixture(false);mask=(x-70).^2+(y-55).^2<=25^2;
raw=raw-20*exp(-((x+y-125)/2).^2);
[score,~,info]=detectViterbiPombeDivisionFrame.scoreRectifiedSeptum(raw,mask);
verifyGreaterThan(testCase,score,1.5);verifyEqual(testCase,info.axisMode,'orientation_search');
verifyLessThan(testCase,info.axisConfidence,.2);
end

function testFlatAndEmptyMasksAreNotEvents(testCase)
[raw,mask]=fixture(false);
score=detectViterbiPombeDivisionFrame.scoreRectifiedSeptum(100*ones(size(raw)),mask);
verifyEqual(testCase,score,0);
score=detectViterbiPombeDivisionFrame.scoreRectifiedSeptum(raw,false(size(mask)));
verifyTrue(testCase,isnan(score));
end

function testEpisodesKeepIsolatedCandidatesAndSeparateLocations(testCase)
episodes=detectViterbiPombeDivisionFrame.rectifiedSeptumEpisodes(1:6, ...
    [2 0 2 3 4 5],[.5 .5 .5 .52 .8 .81],[0 0 179 1 0 0]);
verifyEqual(testCase,[episodes.onset],[1 3 5]);
verifyEqual(testCase,[episodes.peak],[1 4 6]);
verifyEqual(testCase,[episodes.confirmed],[false true true]);
verifyError(testCase,@()detectViterbiPombeDivisionFrame.rectifiedSeptumEpisodes( ...
    1:3,[2 2],[.5 .5],[0 0]),'pombe:EpisodeSize');
end
