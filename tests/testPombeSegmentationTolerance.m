function tests=testPombeSegmentationTolerance
tests=functiontests(localfunctions);
end

function setupOnce(tc)
pluginRoot=fileparts(fileparts(mfilename('fullpath')));
repo=fullfile(fileparts(pluginRoot),'DetecDiv');
addpath(repo);detecdiv_setup_path(repo,'ResetPath',false,'Verbose',false);
addpath(fullfile(pluginRoot,'plugins','processor'),'-begin');
end

function [r,p]=fixture(mode)
[x,y]=meshgrid(1:100,1:80);
mother=y>=30 & y<=50 & x>=25 & x<=75;
small=y>=37 & y<=42 & x>=40 & x<=48;
daughter1=y>=30 & y<=50 & x>=25 & x<=48;
daughter2=y>=30 & y<=50 & x>=52 & x<=75;
stack=zeros(80,100,2,8);
for f=1:8
    lab=double(mother);
    if strcmp(mode,'singleGap') && f==5, lab=double(small); end
    if strcmp(mode,'twoGaps') && any(f==[5 6]), lab=double(small); end
    if strcmp(mode,'split') && f>=5, lab=double(daughter1)+2*double(daughter2); end
    if strcmp(mode,'tailSplit') && f==8, lab=double(daughter1)+2*double(daughter2); end
    stack(:,:,1,f)=100+.01*x+.02*y;stack(:,:,2,f)=lab;
end
r=roi(mode,[]);r.image=stack;r.channelid=[1 2];r.display.channel={'DIC','instances'};
p=detectViterbiPombeDivisionFrame.setparam();p.instanceChannelName='instances';p.rawChannelName='DIC';
p.septumMethod='profile';p.segmentationMaxGapFrames=2;p.splitConfirmationFrames=2;
end

function testOneBadFrameIsMissingAndTrackingResumes(tc)
[r,p]=fixture('singleGap');[out,data]=detectViterbiPombeDivisionFrame.core(p,r,[]);
t=data(end).data;
verifyTrue(tc,all(t.trackValid([1:4 6:8])));verifyFalse(tc,t.trackValid(5));
verifyTrue(tc,isnan(t.septumScore(5)));verifyTrue(tc,t.segmentationGapRejected(5));
verifyEqual(tc,nnz(r.image(:,:,end,5)),0);verifyEmpty(tc,out.stopFrame);
verifyTrue(tc,all(out.trackCandidateIndex([1:4 6:8])==1));
end

function testTwoBadFramesRecoverWithinConfiguredLimit(tc)
[r,p]=fixture('twoGaps');[out,data]=detectViterbiPombeDivisionFrame.core(p,r,[]);
t=data(end).data;verifyEqual(tc,find(t.segmentationGapRejected)',[5 6]);
verifyTrue(tc,all(t.trackValid([1:4 7:8])));verifyFalse(tc,any(t.trackValid(5:6)));
verifyEmpty(tc,out.stopFrame);
end

function testGapCanBeBridgedPastAnUnrelatedLargeObject(tc)
[r,p]=fixture('singleGap');
% A different cell remains segmented while the selected mother is missing.
r.image(2:28,72:99,2,5)=2;
[out,data]=detectViterbiPombeDivisionFrame.core(p,r,[]);
t=data(end).data;
verifyTrue(tc,t.segmentationGapRejected(5));verifyFalse(tc,t.trackValid(5));
verifyEqual(tc,out.trackCandidateIndex(6),1);verifyEmpty(tc,out.stopFrame);
end

function testPersistentDivisionStopsAtLastMotherFrame(tc)
[r,p]=fixture('split');[out,data]=detectViterbiPombeDivisionFrame.core(p,r,[]);
t=data(end).data;verifyEqual(tc,out.stopFrame,4);verifyEqual(tc,out.splitFrameCandidate,5);
verifyEqual(tc,out.splitConfirmedFrame,6);verifyFalse(tc,any(t.trackValid(5:end)));
verifyFalse(tc,any(t.segmentationGapRejected));
end

function testUnconfirmedLastFrameDoesNotStopTracking(tc)
[r,p]=fixture('tailSplit');[out,data]=detectViterbiPombeDivisionFrame.core(p,r,[]);
verifyEmpty(tc,out.stopFrame);verifyTrue(tc,data(end).data.trackValid(8));
verifyTrue(tc,all(isnan(data(end).data.splitConfirmedFrame)));
end

function testSparseSelectionCannotConfirmConsecutiveFrames(tc)
[r,p]=fixture('split');p.segmentationMaxGapFrames=0;
[out,~]=detectViterbiPombeDivisionFrame.core(p,r,[1 2 3 4 5 7 8]);
verifyEmpty(tc,out.stopFrame);
end

function testLegacyDefaultsKeepImmediateStopAndOriginalSchema(tc)
[r,p]=fixture('singleGap');p.segmentationMaxGapFrames=0;p.splitConfirmationFrames=1;
[out,data]=detectViterbiPombeDivisionFrame.core(p,r,[]);
verifyEqual(tc,out.stopFrame,4);verifyEqual(tc,width(data(end).data),9);
verifyFalse(tc,any(data(end).data.trackValid(5:end)));
end
