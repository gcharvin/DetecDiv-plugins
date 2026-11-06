function tests=testPombeFocusQuality
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(mfilename('fullpath')));repo=fullfile(fileparts(root),'DetecDiv');
addpath(repo);detecdiv_setup_path(repo,'ResetPath',false,'Verbose',false);
addpath(fullfile(root,'plugins/processor'),'-begin');
end
function [r,p]=fixture(bad)
if nargin<1,bad=5;end
[xx,yy]=meshgrid(1:120,1:60);a=1000+200*sin(xx*1.4)+150*cos(yy*1.7)+80*sin(xx*.6+yy*.4);
a(15:18,:)=a(15:18,:)-350;a(44:47,:)=a(44:47,:)-350;
r=roi('focus',[]);r.image=zeros(60,120,2,10);r.channelid=[1 2];r.display.channel={'raw','instances'};
for f=1:10
    r.image(:,:,1,f)=a;r.image(22:38,30:58,2,f)=4;r.image(22:38,65:90,2,f)=1;
end
for f=bad
    r.image(:,:,1,f)=imgaussfilt(a,3);
    % Corrupted segmentation on the blurred image must never influence tracking.
    r.image(:,:,2,f)=0;r.image(22:30,30:40,2,f)=9;
end
p=detectViterbiPombeDivisionFrame.setparam();p.instanceChannelName='instances';p.rawChannelName='raw';
p.targetSelectionMode='trap_back';p.anchorMode='left';p.targetCavityBounds=[.2 .3 .6 .4];
p.focusQualityEnabled=true;p.septumMethod='profile';
end
function testBlurExcludedButInputMasksPreserved(tc)
[r,p]=fixture();input=r.image;[o,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyEqual(tc,find(t.focusRejected),5);verifyFalse(tc,t.trackValid(5));verifyTrue(tc,isnan(t.septumScore(5)));
verifyFalse(tc,t.septumDetected(5));verifyEqual(tc,t.targetSelectionState(5),5);
verifyEqual(tc,r.image(:,:,1:2,:),input);verifyFalse(tc,any(r.image(:,:,end,5),'all'));
verifyEqual(tc,o.focusRejectedFrames,5);verifyEqual(tc,t.targetSourceLabel(6),4);
verifyEqual(tc,t.targetIdentitySegment(4),t.targetIdentitySegment(6));verifyEqual(tc,t.targetLinkState(6),3);
end
function testSeveralRejectedFramesDoNotConsumeIdentityRecoveryLimit(tc)
[r,p]=fixture(4:7);[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyEqual(tc,find(t.focusRejected),(4:7)');verifyTrue(tc,all(t.trackValid([1:3 8:10])));
verifyEqual(tc,t.targetIdentitySegment(3),t.targetIdentitySegment(8));
end
function testLockedIdentityAlsoResumesAfterLongExcludedRun(tc)
[r,p]=fixture(4:7);p.targetSelectionMode='locked_depth';p.trapDepthDirection='left';
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyTrue(tc,all(t.trackValid([1:3 8:10])));verifyEqual(tc,t.targetSelectionState(8),1);
verifyFalse(tc,any(t.targetSelectionState==4));
end
function testLegacySplitStopIgnoresCorruptBlurMask(tc)
[r,p]=fixture();p.targetSelectionMode='legacy_viterbi';p.stopAtSplit=true;
[o,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyTrue(tc,all(t.trackValid([1:4 6:10])));verifyFalse(tc,t.trackValid(5));verifyEmpty(tc,o.stopFrame);
end
function testGainOffsetDoesNotChangeFocusDecisions(tc)
[r,p]=fixture();a=r.image(:,:,1,:);q=detectViterbiPombeDivisionFrame.scoreFocusQuality(a,p);
z=detectViterbiPombeDivisionFrame.scoreFocusQuality(3.7*a+12000,p);
verifyEqual(tc,z.rejected,q.rejected);verifyEqual(tc,z.detailRatio,q.detailRatio,'AbsTol',1e-10);
verifyEqual(tc,z.edgeRatio,q.edgeRatio,'AbsTol',1e-10);
end
function testSparseRequestUsesFullMovieQualityReference(tc)
[r,p]=fixture();[o,ds]=detectViterbiPombeDivisionFrame.core(p,r,[4 5 6]);t=ds(end).data;
verifyEqual(tc,t.frame,[4;5;6]);verifyEqual(tc,t.focusRejected,[false;true;false]);
verifyEqual(tc,o.focusQualityDiagnostic.referenceFrameCount,10);
end
function testFlatMovieAllRejectedWithoutInventedScores(tc)
[r,p]=fixture();r.image(:,:,1,:)=100;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyTrue(tc,all(t.focusRejected));verifyTrue(tc,all(isnan(t.septumScore)));
verifyFalse(tc,any(t.trackValid));verifyEqual(tc,t.targetSelectionState,5*ones(10,1));
end
function testOptInPreservesLegacySchemaWhenDisabled(tc)
[r,p]=fixture();p.focusQualityEnabled=false;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyFalse(tc,ismember('focusRejected',t.Properties.VariableNames));verifyTrue(tc,t.trackValid(5));
end
