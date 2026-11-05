function tests=testPombeLockedTarget
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(mfilename('fullpath')));repo=fullfile(fileparts(root),'DetecDiv');
addpath(repo);detecdiv_setup_path(repo,'ResetPath',false,'Verbose',false);
addpath(fullfile(root,'plugins/processor'),'-begin');
end
function [r,p]=fixture()
r=roi('locked',[]);r.image=zeros(60,120,2,8);
r.image(:,:,1,:)=100;r.channelid=[1 2];r.display.channel={'raw','instances'};
for f=1:8,r.image(20:40,10:30,2,f)=1;end
r.image(20:40,85:110,2,3:8)=2;
p=detectViterbiPombeDivisionFrame.setparam();p.instanceChannelName='instances';p.rawChannelName='raw';
p.targetSelectionMode='locked_depth';p.septumMethod='profile';p.stopAtSplit=false;
end
function testWaitForBackCellAndIgnoreLabelOrder(tc)
[r,p]=fixture();[out,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);
t=ds(end).data;verifyFalse(tc,any(t.trackValid(1:2)));verifyTrue(tc,all(t.trackValid(3:8)));
verifyEqual(tc,t.targetSourceLabel(3:8),2*ones(6,1));
verifyEqual(tc,t.targetSelectionState(1:2),zeros(2,1));
verifyEqual(tc,out.targetSelectionDiagnostic.direction,'right');
end
function testMissingTargetDoesNotSwitchToVisibleNeighbour(tc)
[r,p]=fixture();r.image(20:40,85:110,2,5:6)=0;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyFalse(tc,any(t.trackValid(5:6)));verifyTrue(tc,all(t.trackValid([3 4 7 8])));
verifyTrue(tc,all(isnan(t.septumScore(5:6))));
end
function testLongLossIsTerminalEvenIfOtherCellArrivesAtBack(tc)
[r,p]=fixture();r.image(20:40,85:110,2,5:7)=0;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyFalse(tc,any(t.trackValid(5:8)));verifyEqual(tc,t.targetSelectionState(7:8),[4;4]);
end
function testAmbiguousDepthAbstains(tc)
[r,p]=fixture();r.image(42:58,85:110,2,3:8)=3;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyFalse(tc,any(t.trackValid));verifyEqual(tc,t.targetSelectionState(3:8),3*ones(6,1));
end
function testLabelChangeDoesNotChangeIdentity(tc)
[r,p]=fixture();r.image(20:40,85:110,2,5:8)=7;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyTrue(tc,all(t.trackValid(3:8)));verifyEqual(tc,t.targetSourceLabel(5:8),7*ones(4,1));
end
function testLeftDirectionAndAbsentTarget(tc)
[r,p]=fixture();r.image=flip(r.image,2);p.trapDepthDirection='left';
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);verifyTrue(tc,all(ds(end).data.trackValid(3:8)));
[r,p]=fixture();r.image(:,:,2,:)=0;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);
verifyTrue(tc,all(ds(end).data.targetSelectionState==0));
end
function testTransientBackMaskCannotInitializeTarget(tc)
[r,p]=fixture();r.image(20:40,85:110,2,1)=3;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);
verifyFalse(tc,any(ds(end).data.trackValid(1:2)));verifyTrue(tc,ds(end).data.trackValid(3));
end
function testGrowingTargetMayCrossInitializationDepth(tc)
[r,p]=fixture();r.image(:,:,2,:)=0;
for f=1:8,r.image(20:40,(85-4*f):(110-4*f),2,f)=2;end
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyTrue(tc,all(t.trackValid));verifyLessThan(tc,t.targetDepth(end),.6);
end
