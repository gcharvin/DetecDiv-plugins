function tests=testPombeTrapBack
tests=functiontests(localfunctions);
end
function setupOnce(~)
root=fileparts(fileparts(mfilename('fullpath')));repo=fullfile(fileparts(root),'DetecDiv');
addpath(repo);detecdiv_setup_path(repo,'ResetPath',false,'Verbose',false);
addpath(fullfile(root,'plugins/processor'),'-begin');
end
function [r,p]=fixture()
r=roi('trap',[]);r.image=zeros(60,120,2,10);r.image(:,:,1,:)=100;
r.channelid=[1 2];r.display.channel={'raw','instances'};
for f=1:10
    r.image(22:38,30:58,2,f)=4;r.image(22:38,65:90,2,f)=1;
end
p=detectViterbiPombeDivisionFrame.setparam();p.instanceChannelName='instances';
p.rawChannelName='raw';p.targetSelectionMode='trap_back';p.anchorMode='left';
p.targetCavityBounds=[.2 .3 .6 .4];p.septumMethod='profile';
end
function testSelectLeftBackRatherThanFirstLabel(tc)
[r,p]=fixture();[o,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyTrue(tc,all(t.trackValid));verifyEqual(tc,t.targetSourceLabel,4*ones(10,1));
verifyEqual(tc,o.targetSelectionDiagnostic.direction,'left');
end
function testLongMotherPoleCanReachBackWithCenterOutsideOldGate(tc)
[r,p]=fixture();r.image(:,:,2,:)=0;r.image(22:38,30:90,2,:)=2;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);verifyTrue(tc,all(ds(end).data.trackValid));
end
function testMissingFramesRemainEmptyAndLongGapDoesNotKillMovie(tc)
[r,p]=fixture();r.image(22:38,30:58,2,3:6)=0;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyFalse(tc,any(t.trackValid(3:6)));verifyTrue(tc,all(t.trackValid([1 2 7:10])));
verifyTrue(tc,all(isnan(t.septumScore(3:6))));
verifyEqual(tc,t.targetLinkState(7),4);verifyEqual(tc,t.targetIdentitySegment(7),2);
end
function testSplitSelectsBackDaughterAndMarksIdentityBreak(tc)
[r,p]=fixture();r.image(:,:,2,:)=0;r.image(22:38,30:90,2,1:4)=3;
r.image(22:38,30:55,2,5:10)=8;r.image(22:38,60:90,2,5:10)=2;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyTrue(tc,all(t.trackValid));verifyEqual(tc,t.targetSourceLabel(5:10),8*ones(6,1));
verifyEqual(tc,t.targetLinkState(5),4);verifyEqual(tc,t.targetIdentitySegment(5),2);
end
function testOutsideCavityArtifactCannotWin(tc)
[r,p]=fixture();r.image(1:14,2:15,2,:)=6;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);
verifyEqual(tc,ds(end).data.targetSourceLabel,4*ones(10,1));
end
function testAmbiguousBackAbstains(tc)
[r,p]=fixture();r.image(:,:,2,:)=0;r.image(20:26,30:58,2,:)=1;
r.image(33:40,30:58,2,:)=2;
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);t=ds(end).data;
verifyFalse(tc,any(t.trackValid));verifyEqual(tc,t.targetSelectionState,3*ones(10,1));
end
function testMirroredFilmUsesItsOwnDirection(tc)
[r,p]=fixture();r.image=flip(r.image,2);p.anchorMode='right';
[~,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);
verifyEqual(tc,ds(end).data.targetSourceLabel,4*ones(10,1));
end
function testExistingSelectorOverridesObsoleteDirection(tc)
[r,p]=fixture();p.trapDepthDirection='right';
[o,ds]=detectViterbiPombeDivisionFrame.core(p,r,[]);
verifyEqual(tc,ds(end).data.targetSourceLabel,4*ones(10,1));
verifyEqual(tc,o.targetSelectionDiagnostic.directionSource,'anchorMode');
end
function testCalibrationIsRequired(tc)
[r,p]=fixture();p.targetCavityBounds=[];
verifyError(tc,@()detectViterbiPombeDivisionFrame.core(p,r,[]),'pombe:TrapBounds');
end
