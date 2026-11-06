function tests=testPombeSeptumSupport
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(mfilename('fullpath')));repo=fullfile(fileparts(root),'DetecDiv');
addpath(repo);detecdiv_setup_path(repo,'ResetPath',false,'Verbose',false);addpath(fullfile(root,'plugins/processor'),'-begin');
end
function [r,p]=fixture(mode)
r=roi('support',[]);r.image=zeros(64,120,2,3);r.channelid=[1 2];r.display.channel={'raw','instances'};
r.image(:,:,1,:)=100;r.image(23:41,30:90,2,1)=1;
for f=2:3
 r.image(23:41,30:57,2,f)=2;r.image(23:41,60:90,2,f)=3;r.image(23:41,58:60,1,f)=20;
end
if strcmp(mode,'missing'),r.image(23:41,30:57,2,2)=0;end
if strcmp(mode,'preexisting'),r.image(:,:,2,1)=r.image(:,:,2,2);end
if strcmp(mode,'separated'),r.image(23:41,30:57,2,2)=0;r.image(23:41,30:52,2,2)=2;end
p=detectViterbiPombeDivisionFrame.setparam();p.instanceChannelName='instances';p.rawChannelName='raw';p.targetSelectionMode='trap_back';p.anchorMode='right';p.targetCavityBounds=[.2 .3 .6 .4];p.septumBoundarySupportEnabled=true;p.stopAtSplit=false;
end
function testPairedDaughtersScoreInterfaceWithoutChangingSegmentation(tc)
[r,p]=fixture('paired');input=r.image;[o,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyEqual(tc,t.septumSupportState(2),1);verifyGreaterThan(tc,t.septumScore(2),1.5);verifyEqual(tc,t.septumOriginalScore(2),0);
verifyEqual(tc,r.image(:,:,1:2,:),input);id=r.findChannelID(p.outputMaskChannelName);support=r.findChannelID(o.septumSupportChannelName);
verifyEqual(tc,r.image(:,:,id,2)>0,input(:,:,2,2)==3);verifyGreaterThan(tc,nnz(r.image(:,:,support,2)),nnz(r.image(:,:,id,2)));
verifyEqual(tc,t.septumSupportParentFrame(2),1);verifyTrue(tc,t.septumScorable(2));
end
function testMissingHalfAbstainsAndNeverCopiesHistoricalMask(tc)
[r,p]=fixture('missing');[o,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyEqual(tc,t.septumSupportState(2),2);verifyTrue(tc,isnan(t.septumScore(2)));verifyFalse(tc,t.septumDetected(2));verifyFalse(tc,t.septumScorable(2));
id=r.findChannelID(o.septumSupportChannelName);verifyFalse(tc,any(r.image(:,:,id,2),'all'));verifyTrue(tc,t.trackValid(2));
end
function testPreexistingNeighboursAreNotMerged(tc)
[r,p]=fixture('preexisting');[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);verifyEqual(tc,ds(end).data.septumSupportState,zeros(3,1));
end
function testSeparatedDaughtersAreNotBridged(tc)
[r,p]=fixture('separated');[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);verifyEqual(tc,ds(end).data.septumSupportState(2),2);
end
function testSparseRequestDoesNotUseUnprocessedParent(tc)
[r,p]=fixture('paired');[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,2);verifyEqual(tc,ds(end).data.septumSupportState,0);
end
function testDisabledModeKeepsHistoricalScoreAndSchema(tc)
[r,p]=fixture('paired');p.septumBoundarySupportEnabled=false;[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyFalse(tc,ismember('septumSupportState',t.Properties.VariableNames));verifyEqual(tc,t.septumScore(2),0);
end
function testEmptyMovieHasExplicitUnscorableSchema(tc)
[r,p]=fixture('paired');r.image(:,:,2,:)=0;[o,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyFalse(tc,any(t.septumScorable));verifyTrue(tc,all(isnan(t.septumScore)));
id=r.findChannelID(o.septumSupportChannelName);verifyFalse(tc,any(r.image(:,:,id,:),'all'));
end
