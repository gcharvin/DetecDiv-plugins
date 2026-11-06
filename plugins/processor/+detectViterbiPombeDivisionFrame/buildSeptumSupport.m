function [support,d]=buildSeptumSupport(target,candidates,frames,p)
%BUILDSEPTUMSUPPORT Preserve observed daughter interfaces at a recent split.
% This is a scoring region, never a replacement segmentation or target choice.
% A previous mask may justify pairing two CURRENT instances, but cannot supply
% missing pixels on its own. Missing-half cases explicitly abstain.
[H,W,~,~]=size(target);support=target;
d=struct('state',zeros(numel(frames),1),'parentFrame',nan(numel(frames),1), ...
    'scorable',false(numel(frames),1),'partnerLabel',nan(numel(frames),1), ...
    'stateLegend',{{'0 current target only','1 two observed daughters supported by a recent parent', ...
    '2 partial mask after area loss: missing or ambiguous partner; no score'}}, ...
    'lookbackReliableFrames',2,'sourceSegmentationUnmodified',true, ...
    'onsetIsNotEstablishedByASplit',true);
excluded=[];if isfield(p,'qualityExcludedFrames'),excluded=p.qualityExcludedFrames;end
for k=1:numel(frames)
    f=frames(k);M=target(:,:,1,f)>0;area=nnz(M);
    if area==0,continue;end
    d.scorable(k)=true;
    previous=frames(frames<f);previous=previous(~ismember(previous,excluded));
    previous=previous(arrayfun(@(r)sum(~ismember(r+1:f-1,excluded))<=2,previous));
    for ref=fliplr(previous)
        P=target(:,:,1,ref)>0;pa=nnz(P);if pa==0,continue;end
        ratio=area/pa;overlap=nnz(M&P)/area;
        if ratio<.30||ratio>.80||overlap<.75,continue;end
        % Current mask is a substantially smaller piece of a recent mother.
        partners={};labels=[];
        for j=1:numel(candidates{f})
            N=false(H,W);N(candidates{f}(j).PixelIdxList)=true;na=nnz(N);
            if any(N&M,'all')||na<.20*pa||nnz(N&P)/na<.75,continue;end
            U=M|N;
            if nnz(U&P)/pa<.75||nnz(U)/pa<.75||nnz(U)/pa>1.35,continue;end
            % Do not bridge a separated daughter or a distant neighbour.
            distance=bwdist(M);if min(distance(N))>3,continue;end
            U=imfill(imclose(U,strel('disk',2,0)),'holes');
            cc=bwconncomp(U);if cc.NumObjects~=1,continue;end
            partners{end+1}=U;labels(end+1)=candidates{f}(j).Label;
        end
        d.parentFrame(k)=ref;
        if numel(partners)==1
            support(:,:,1,f)=uint16(partners{1});d.state(k)=1;
            d.partnerLabel(k)=labels(1);d.scorable(k)=true;
        else
            % A historical outline is not evidence of the missing half NOW.
            support(:,:,1,f)=0;d.state(k)=2;d.scorable(k)=false;
        end
        break;
    end
end
end
