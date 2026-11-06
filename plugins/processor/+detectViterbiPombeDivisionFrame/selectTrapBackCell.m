function [track,costs,gaps,d]=selectTrapBackCell(candidates,frames,imageSize,p)
%SELECTTRAPBACKCELL Observe the resident at a calibrated trap back each frame.
% Selection and identity continuity are separate. Missing masks stay missing;
% a later observation is not silently asserted to be the same biological cell.
% Use the existing selector setting, not a second independent orientation.
direction=choice(p,'anchorMode','');
if ~ismember(direction,{'left','right','up','down'})
    error('pombe:TrapDirection','Set anchorMode to left, right, up or down from the raw movie for trap_back selection.');
end
box=field(p,'targetCavityBounds',[]);
if isempty(box)
    error('pombe:TrapBounds','Set targetCavityBounds from the raw movie before selecting its resident cell.');
end
validateattributes(box,{'numeric'},{'vector','numel',4,'finite','nonnegative'});
box=double(box(:)');
if any(box(3:4)<=0)||any(box(1:2)+box(3:4)>1)
    error('pombe:TrapBounds','Cavity bounds must be normalized [x y width height] inside the ROI.');
end
backFraction=field(p,'targetBackFraction',.30);
insideMin=field(p,'targetMinCavityFraction',.5);
margin=field(p,'targetDepthMargin',.03);
overlapMin=field(p,'targetMinOverlap',.5);
maxGap=field(p,'targetRecoveryMaxGap',2);
qualityExcluded=field(p,'qualityExcludedFrames',[]);
validateattributes(backFraction,{'numeric'},{'scalar','>',0,'<=',1,'finite'});
validateattributes(insideMin,{'numeric'},{'scalar','>',0,'<=',1,'finite'});
validateattributes(margin,{'numeric'},{'scalar','>=',0,'finite'});
validateattributes(overlapMin,{'numeric'},{'scalar','>',0,'<=',1,'finite'});
validateattributes(maxGap,{'numeric'},{'scalar','integer','>=',0,'finite'});
track=zeros(1,numel(candidates));costs=nan(size(frames));gaps=false(size(frames));
states=zeros(size(frames));labels=nan(size(frames));depths=labels;
segments=zeros(size(frames));links=zeros(size(frames));insideCount=zeros(size(frames));
backCount=zeros(size(frames));last=[];lastFrame=NaN;segment=0;
for k=1:numel(frames)
    f=frames(k);cand=candidates{f};pole=nan(1,numel(cand));center=pole;
    for j=1:numel(cand)
        [yy,xx]=ind2sub(imageSize,cand(j).PixelIdxList);
        xy=[double(xx(:))/imageSize(2),double(yy(:))/imageSize(1)];
        within=all(xy>=box(1:2)&xy<=box(1:2)+box(3:4),2);
        centroid=cand(j).Centroid./[imageSize(2) imageSize(1)];
        if mean(within)<insideMin||any(centroid<box(1:2)|centroid>box(1:2)+box(3:4))
            continue;
        end
        insideCount(k)=insideCount(k)+1;
        local=(xy-box(1:2))./box(3:4);
        c=(centroid-box(1:2))./box(3:4);
        switch direction
            case 'left',z=1-local(:,1);center(j)=1-c(1);
            case 'right',z=local(:,1);center(j)=c(1);
            case 'up',z=1-local(:,2);center(j)=1-c(2);
            case 'down',z=local(:,2);center(j)=c(2);
        end
        % A long mother may touch the back with its centre far from it.
        pole(j)=prctile(z,90);
    end
    eligible=find(pole>=1-backFraction);
    backCount(k)=numel(eligible);
    if isempty(eligible)
        if ~isempty(last),states(k)=2;gaps(k)=true;end
        continue;
    end
    % Among back-touching instances choose the deepest CENTRE, so a long
    % neighbour whose pole approaches the back does not beat a small resident.
    [sorted,order]=sort(center(eligible),'descend');
    if numel(order)>1&&sorted(1)-sorted(2)<margin
        states(k)=3;gaps(k)=true;continue;
    end
    chosen=eligible(order(1));current=cand(chosen);
    if isempty(last)
        segment=segment+1;links(k)=1;
    else
        overlap=numel(intersect(last.PixelIdxList,current.PixelIdxList))/max(last.Area,current.Area);
        ratio=current.Area/last.Area;
        costs(k)=1-overlap;
        missingReliable=sum(~ismember(lastFrame+1:f-1,qualityExcluded));
        if overlap>=overlapMin&&ratio>=.65&&ratio<=1.5&&missingReliable<=maxGap
            links(k)=2+(f-lastFrame>1);
        else
            % Split, long gap or replacement: retain the spatial observation,
            % but start a new identity segment instead of inventing continuity.
            segment=segment+1;links(k)=4;
        end
    end
    track(f)=chosen;states(k)=1;labels(k)=current.Label;depths(k)=center(chosen);
    segments(k)=segment;last=current;lastFrame=f;
end
d=struct('mode','trap_back','direction',direction,'cavityBounds',box, ...
    'directionSource','anchorMode', ...
    'backFraction',backFraction,'minCavityFraction',insideMin, ...
    'depthMargin',margin,'minOverlap',overlapMin,'maxGapFrames',maxGap, ...
    'stateLegend',{{'0 no target','1 selected','2 missing observation','3 ambiguous'}}, ...
    'linkLegend',{{'0 no observation','1 first observation','2 overlap link', ...
    '3 short-gap overlap link','4 new segment: split, long gap or replacement'}}, ...
    'state',states(:),'sourceLabel',labels(:),'depth',depths(:), ...
    'identitySegment',segments(:),'linkState',links(:), ...
    'cavityCandidateCount',insideCount(:),'backCandidateCount',backCount(:), ...
    'splitStopApplied',false,'identityIsBiologicallyValidated',false);
end

function v=field(p,name,fallback)
v=fallback;if isfield(p,name)&&~isempty(p.(name)),v=p.(name);end
end
function v=choice(p,name,fallback)
v=field(p,name,fallback);if iscell(v),v=v{end};end;v=char(string(v));
end
