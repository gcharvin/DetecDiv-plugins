function [track,costs,gaps,diagnostic]=trackLockedDepth(candidates,frames,imageSize,p)
%TRACKLOCKEDDEPTH Initialize only in the trap-back region, then lock identity.
% Depth is explicitly defined in normalized ROI coordinates, not inferred
% from which masks happen to exist. No late restart on another cell.
direction=setting(p,'trapDepthDirection','right');
floorDepth=setting(p,'targetMinDepth',.60);
depthMargin=setting(p,'targetDepthMargin',.03);
overlapMin=setting(p,'targetMinOverlap',.5);
matchMargin=setting(p,'targetMatchMargin',.1);
maxGap=setting(p,'targetRecoveryMaxGap',2);
validateattributes(floorDepth,{'numeric'},{'scalar','>=',0,'<=',1});
validateattributes(depthMargin,{'numeric'},{'scalar','nonnegative','finite'});
validateattributes(overlapMin,{'numeric'},{'scalar','positive','<=',1});
validateattributes(matchMargin,{'numeric'},{'scalar','nonnegative','finite'});
validateattributes(maxGap,{'numeric'},{'scalar','integer','nonnegative','finite'});
if ~ismember(direction,{'right','left','up','down'})
    error('pombe:TrapDirection','Trap depth direction must be right, left, up or down.');
end
track=zeros(1,numel(candidates));costs=nan(size(frames));gaps=false(size(frames));
states=zeros(size(frames));labels=nan(size(frames));depths=labels;
previous=[];lastFrame=NaN;lost=false;
for k=1:numel(frames)
    f=frames(k);cand=candidates{f};
    if lost,states(k)=4;continue;end
    depth=zeros(1,numel(cand));
    for j=1:numel(cand)
        xy=cand(j).Centroid./[imageSize(2) imageSize(1)];
        switch direction
            case 'right',depth(j)=xy(1);
            case 'left',depth(j)=1-xy(1);
            case 'down',depth(j)=xy(2);
            case 'up',depth(j)=1-xy(2);
        end
    end
    % The back region gates INITIALIZATION only. A growing mother may move
    % its centroid toward the mouth without changing biological identity.
    if isempty(previous),eligible=find(depth>=floorDepth);else,eligible=1:numel(cand);end
    chosen=[];state=0;
    if isempty(previous)
        [sorted,order]=sort(depth(eligible),'descend');
        if ~isempty(order)
            if numel(order)>1 && sorted(1)-sorted(2)<depthMargin
                state=3;
            else
                chosen=eligible(order(1));
                % Reject transient masks (notably degraded source frames)
                % before committing the target identity. Backfill this seed
                % only when the next acquired frame supports the same cell.
                if k==numel(frames) || frames(k+1)~=f+1
                    chosen=[];
                else
                    next=candidates{frames(k+1)};strengths=[];
                    for q=1:numel(next)
                        a=cand(chosen);b=next(q);ratio=b.Area/a.Area;
                        overlap=numel(intersect(a.PixelIdxList,b.PixelIdxList))/max(a.Area,b.Area);
                        if ratio>=.65 && ratio<=1.5 && overlap>=overlapMin
                            strengths(end+1)=overlap; %#ok<AGROW>
                        end
                    end
                    strengths=sort(strengths,'descend');
                    if isempty(strengths),chosen=[];
                    elseif numel(strengths)>1 && strengths(1)-strengths(2)<matchMargin
                        chosen=[];state=3;
                    end
                end
            end
        end
    else
        if f-lastFrame-1>maxGap,lost=true;states(k)=4;continue;end
        strengths=zeros(size(eligible));
        for j=1:numel(eligible)
            current=cand(eligible(j));ratio=current.Area/previous.Area;
            overlap=numel(intersect(previous.PixelIdxList,current.PixelIdxList))/ ...
                max(previous.Area,current.Area);
            if ratio>=.65 && ratio<=1.5 && overlap>=overlapMin
                strengths(j)=overlap;
            end
        end
        [sorted,order]=sort(strengths,'descend');
        state=2;
        if ~isempty(order) && sorted(1)>0
            if numel(order)>1 && sorted(2)>0 && sorted(1)-sorted(2)<matchMargin
                state=3;
            else
                chosen=eligible(order(1));costs(k)=1-sorted(1);
            end
        end
    end
    if ~isempty(chosen)
        track(f)=chosen;states(k)=1;labels(k)=cand(chosen).Label;depths(k)=depth(chosen);
        previous=cand(chosen);lastFrame=f;if isnan(costs(k)),costs(k)=0;end
    else
        states(k)=state;
        if ~isempty(previous)
            gaps(k)=true;
            if f-lastFrame>maxGap,states(k)=4;lost=true;end
        end
    end
end
diagnostic=struct('mode','locked_depth','direction',direction,'minDepth',floorDepth, ...
    'depthMargin',depthMargin,'minOverlap',overlapMin,'matchMargin',matchMargin, ...
    'maxGapFrames',maxGap,'areaRatioRange',[.65 1.5], ...
    'initializationSupportFrames',2, ...
    'stateLegend',{{'0 waiting for target','1 locked','2 missing','3 ambiguous','4 lost (no restart)'}}, ...
    'state',states(:),'sourceLabel',labels(:),'depth',depths(:));
end

function value=setting(p,name,fallback)
value=fallback;if isfield(p,name)&&~isempty(p.(name)),value=p.(name);end
if iscell(value),value=value{end};end
if isstring(value),value=char(value);end
end
