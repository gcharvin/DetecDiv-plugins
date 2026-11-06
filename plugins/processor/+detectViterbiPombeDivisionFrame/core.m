function [paramout, dataout, imageout] = core(paramout, roiobj, frames)
% detectViterbiPombeDivisionFrame.core  Track target cell and score septum.

if nargin < 3
    frames = [];
end

if isempty(roiobj.image)
    roiobj.load;
end

instanceName = readChoiceLocal(paramout.instanceChannelName);
rawName = readChoiceLocal(paramout.rawChannelName);
if isempty(instanceName)
    error('detectViterbiPombeDivisionFrame:NoInstanceChannel', ...
        'No instance mask channel selected.');
end
if isempty(rawName)
    error('detectViterbiPombeDivisionFrame:NoRawChannel', ...
        'No raw image channel selected.');
end

instanceID = roiobj.findChannelID(instanceName);
rawID = roiobj.findChannelID(rawName);
if isempty(instanceID)
    error('detectViterbiPombeDivisionFrame:InstanceChannelNotFound', ...
        'Instance channel "%s" not found in ROI.', instanceName);
end
if isempty(rawID)
    error('detectViterbiPombeDivisionFrame:RawChannelNotFound', ...
        'Raw image channel "%s" not found in ROI.', rawName);
end
instanceID = instanceID(1);
rawID = rawID(1);

maskStack = roiobj.image(:, :, instanceID, :);
rawStack = roiobj.image(:, :, rawID, :);
[H, W, ~, T] = size(maskStack);
frames = normalizeFrames(frames, T);
quality=[];trackingFrames=frames;trackingParam=paramout;
if scalarParam(paramout,'focusQualityEnabled',0)>0
    quality=detectViterbiPombeDivisionFrame.scoreFocusQuality(rawStack,paramout);
    trackingFrames=frames(~quality.rejected(frames));
    trackingParam.qualityExcludedFrames=find(quality.rejected)';
    paramout.focusQualityDiagnostic=quality;
    paramout.focusRejectedFrames=find(quality.rejected)';
end

inputMode = readChoiceLocal(paramout.inputMode);
if isempty(inputMode), inputMode = 'auto'; end

candidates = cell(1, T);
for f = trackingFrames
    lab = normalizeLabelFrame(maskStack(:, :, 1, f), inputMode);
    candidates{f} = frameCandidates(lab, paramout);
end

targetMode=readChoiceLocal(fieldOr(paramout,'targetSelectionMode','legacy_viterbi'));
if ~ismember(targetMode,{'legacy_viterbi','locked_depth','trap_back'})
    error('pombe:TargetSelectionMode','Unknown target selection mode: %s',targetMode);
end
targetDiagnostic=[];
if strcmp(targetMode,'locked_depth')
    [track,costs,bridgedGaps,targetDiagnostic]= ...
        detectViterbiPombeDivisionFrame.trackLockedDepth(candidates,trackingFrames,[H W],trackingParam);
end
if strcmp(targetMode,'trap_back')
    [track,costs,bridgedGaps,targetDiagnostic]= ...
        detectViterbiPombeDivisionFrame.selectTrapBackCell(candidates,trackingFrames,[H W],trackingParam);
end
if all(cellfun(@isempty, candidates(frames)))
    warning('detectViterbiPombeDivisionFrame:NoCandidates', ...
        'No mask candidates found in "%s". Output will be empty.', instanceName);
    outMask = zeros(H, W, 1, T, 'uint16');
    [profileDs, scoreDs, paramout] = buildEmptyDataseries(paramout, roiobj, frames);
    [profileDs, scoreDs] = addToleranceDiagnostics(profileDs, scoreDs, paramout, false(numel(frames),1), []);
    targetDiagnostic=expandTargetQuality(targetDiagnostic,trackingFrames,frames,quality);
    [profileDs,scoreDs]=addTargetDiagnostics(profileDs,scoreDs,targetDiagnostic);
    [profileDs,scoreDs]=addFocusDiagnostics(profileDs,scoreDs,quality,frames);
    if scalarParam(paramout,'septumBoundarySupportEnabled',0)>0
        [supportMask,supportDiagnostic]=detectViterbiPombeDivisionFrame.buildSeptumSupport(outMask,candidates,frames,trackingParam);
        [profileDs,scoreDs,paramout]=addSupportDiagnostics(profileDs,scoreDs,paramout,supportDiagnostic,scoreDs.data.septumScore);
    end
    paramout.targetSelectionDiagnostic=targetDiagnostic;
    dataout = upsertDataseries(roiobj.data, [profileDs scoreDs]);
    [paramout, dataout, imageout] = writeOutput(roiobj, paramout, outMask, dataout);
    if scalarParam(paramout,'septumBoundarySupportEnabled',0)>0
        [paramout,imageout]=writeSupportOutput(roiobj,paramout,supportMask);
    end
    return;
end

if strcmp(targetMode,'legacy_viterbi')
    anchor = resolveAnchor(paramout);
    [track, costs, bridgedGaps] = viterbiTrack(candidates, trackingFrames, anchor, [H W], trackingParam);
    [track, gapRejected] = rejectTransientSegmentation(candidates, track, trackingFrames, trackingParam);
else
    gapRejected=false(size(trackingFrames));
end
gapRejected = gapRejected | bridgedGaps;
[stopFrame, splitFrame, splitScore, confirmedFrame] = detectSplitStop(candidates, track, trackingFrames, paramout);
if ~isempty(quality)
    good=ismember(frames,trackingFrames);expanded=false(size(frames));expanded(good)=gapRejected;gapRejected=expanded;
    expanded=nan(size(frames));expanded(good)=costs;costs=expanded;
    targetDiagnostic=expandTargetQuality(targetDiagnostic,trackingFrames,frames,quality);
end

outMask = zeros(H, W, 1, T, 'uint16');
trackArea = nan(numel(frames), 1);
trackValid = false(numel(frames), 1);
for k = 1:numel(frames)
    f = frames(k);
    if paramout.stopAtSplit && ~strcmp(targetMode,'trap_back') && ~isempty(stopFrame) && f > stopFrame
        continue;
    end
    idx = track(f);
    if idx > 0 && idx <= numel(candidates{f})
        pix = candidates{f}(idx).PixelIdxList;
        outMask(pix + (f - 1) * H * W) = uint16(1);
        trackArea(k) = double(candidates{f}(idx).Area);
        trackValid(k) = true;
    end
end

supportDiagnostic=[];supportMask=outMask;
if scalarParam(paramout,'septumBoundarySupportEnabled',0)>0
    [supportMask,supportDiagnostic]=detectViterbiPombeDivisionFrame.buildSeptumSupport(outMask,candidates,frames,trackingParam);
end
[profileMatrix, septumScore, septumPosition, septumDiagnostics] = computeProfilesAndScores( ...
    rawStack, supportMask, frames, paramout);

[profileDs, scoreDs] = buildDataseries(paramout, roiobj, frames, profileMatrix, ...
    septumScore, septumPosition, trackArea, trackValid, stopFrame, splitFrame, splitScore, septumDiagnostics);
[profileDs, scoreDs] = addToleranceDiagnostics(profileDs, scoreDs, paramout, gapRejected, confirmedFrame);
[profileDs,scoreDs]=addTargetDiagnostics(profileDs,scoreDs,targetDiagnostic);
[profileDs,scoreDs]=addFocusDiagnostics(profileDs,scoreDs,quality,frames);
if ~isempty(supportDiagnostic)
    [~,originalScore]=computeProfilesAndScores(rawStack,outMask,frames,paramout);
    [profileDs,scoreDs,paramout]=addSupportDiagnostics(profileDs,scoreDs,paramout,supportDiagnostic,originalScore);
end

paramout.trackFrames = frames;
paramout.trackCandidateIndex = track(frames);
paramout.viterbiCost = costs;
paramout.stopFrame = stopFrame;
paramout.splitFrameCandidate = splitFrame;
paramout.splitScore = splitScore;
paramout.segmentationGapRejectedFrames = frames(gapRejected);
paramout.splitConfirmedFrame = confirmedFrame;
paramout.targetSelectionDiagnostic=targetDiagnostic;
paramout.inputChannelName = instanceName;
paramout.rawChannelNameResolved = rawName;
paramout.saveChannels = {char(string(paramout.outputMaskChannelName))};

if isfield(paramout, 'debug') && paramout.debug
    fprintf('[detectViterbiPombeDivisionFrame] instance="%s" raw="%s" output="%s" stop=%s split=%s\n', ...
        instanceName, rawName, char(string(paramout.outputMaskChannelName)), mat2str(stopFrame), mat2str(splitFrame));
end

dataout = upsertDataseries(roiobj.data, [profileDs scoreDs]);
[paramout, dataout, imageout] = writeOutput(roiobj, paramout, outMask, dataout);
if ~isempty(supportDiagnostic)
    [paramout,imageout]=writeSupportOutput(roiobj,paramout,supportMask);
end
end

function [profileDs,scoreDs,p]=addSupportDiagnostics(profileDs,scoreDs,p,d,original)
scoreDs.data.septumOriginalScore=original;
scoreDs.data.septumScorable=d.scorable;scoreDs.data.septumSupportState=d.state;
scoreDs.data.septumSupportParentFrame=d.parentFrame;
scoreDs.data.septumSupportPartnerLabel=d.partnerLabel;
scoreDs.userData.septumSupport=d;profileDs.userData.septumSupport=d;p.septumSupportDiagnostic=d;
end
function [p,imageout]=writeSupportOutput(r,p,mask)
name=[p.outputMaskChannelName '_septum_support'];
if ~isempty(r.findChannelID(name)),r.removeChannel(name);end
r.addChannel(mask,name,[.8 .2 1],[0 0 0]);
if ~isfield(p,'saveChannels'),p.saveChannels={p.outputMaskChannelName};end
p.saveChannels{end+1}=name;p.septumSupportChannelName=name;imageout=r.image;
end

function value=fieldOr(s,name,fallback)
value=fallback;if isfield(s,name),value=s.(name);end
end

function d=expandTargetQuality(d,goodFrames,frames,q)
if isempty(d)||isempty(q),return;end
good=ismember(frames,goodFrames);
names={'state','sourceLabel','depth','identitySegment','linkState','cavityCandidateCount','backCandidateCount'};
for i=1:numel(names)
    key=names{i};if ~isfield(d,key),continue;end
    if ismember(key,{'sourceLabel','depth'}),a=nan(numel(frames),1);else,a=zeros(numel(frames),1);end
    a(good)=d.(key);d.(key)=a;
end
d.state(q.rejected(frames))=5;
d.stateLegend{end+1}='5 excluded by focus quality';
d.qualityExcludedFrames=find(q.rejected)';
end

function [profileDs,scoreDs]=addFocusDiagnostics(profileDs,scoreDs,q,frames)
if isempty(q),return;end
scoreDs.data.focusRejected=q.rejected(frames);
scoreDs.data.focusDetailRatio=q.detailRatio(frames);
scoreDs.data.focusEdgeRatio=q.edgeRatio(frames);
scoreDs.data.focusRejectReason=q.reason(frames);
profileDs.userData.focusQuality=q;scoreDs.userData.focusQuality=q;
end

function [profileDs,scoreDs]=addTargetDiagnostics(profileDs,scoreDs,d)
if isempty(d),return;end
scoreDs.data.targetSelectionState=d.state;
scoreDs.data.targetSourceLabel=d.sourceLabel;
scoreDs.data.targetDepth=d.depth;
if isfield(d,'identitySegment')
    scoreDs.data.targetIdentitySegment=d.identitySegment;
    scoreDs.data.targetLinkState=d.linkState;
    scoreDs.data.targetCavityCandidateCount=d.cavityCandidateCount;
    scoreDs.data.targetBackCandidateCount=d.backCandidateCount;
end
profileDs.userData.targetSelection=d;scoreDs.userData.targetSelection=d;
end

function frames = normalizeFrames(frames, T)
if isempty(frames) || (isnumeric(frames) && isequal(frames, -1))
    frames = 1:T;
else
    frames = frames(:).';
    frames = frames(frames >= 1 & frames <= T);
    if isempty(frames), frames = 1:T; end
end
end

function [paramout, dataout, imageout] = writeOutput(roiobj, paramout, outMask, dataout)
outputName = strtrim(char(string(paramout.outputMaskChannelName)));
if isempty(outputName), outputName = 'cell_of_interest'; end
paramout.outputMaskChannelName = outputName;
paramout.outputChannelName = outputName;

if ~isempty(roiobj.findChannelID(outputName))
    roiobj.removeChannel(outputName);
end
roiobj.addChannel(outMask, outputName, [1 0.55 0], [0 0 0]);

roiobj.data = dataout;
imageout = roiobj.image;
end

function lab = normalizeLabelFrame(frame, inputMode)
frame = squeeze(frame);
if isempty(frame)
    lab = zeros(size(frame), 'uint16');
    return;
end

switch lower(inputMode)
    case 'binary'
        lab = bwlabel(frame > 0);
    case 'label'
        lab = uint16(frame);
    otherwise
        vals = unique(frame(:));
        vals(vals == 0) = [];
        if isempty(vals)
            lab = zeros(size(frame), 'uint16');
        elseif isscalar(vals)
            lab = bwlabel(frame > 0);
        else
            lab = uint16(frame);
        end
end
end

function cand = frameCandidates(lab, paramout)
stats = regionprops(lab, 'Area', 'Centroid', 'PixelIdxList', 'BoundingBox', ...
    'MajorAxisLength', 'MinorAxisLength', 'Orientation');
cand = struct('Label', {}, 'Area', {}, 'Centroid', {}, 'PixelIdxList', {}, ...
    'BoundingBox', {}, 'MajorAxisLength', {}, 'MinorAxisLength', {}, 'Orientation', {});
if isempty(stats), return; end

minArea = scalarParam(paramout, 'minArea', 20);
maxArea = scalarParam(paramout, 'maxArea', inf);
for i = 1:numel(stats)
    area = double(stats(i).Area);
    if area < minArea || area > maxArea
        continue;
    end
    item = stats(i);
    item.Label = firstPixelLabel(lab, item.PixelIdxList);
    cand(end+1) = item; %#ok<AGROW>
end
end

function label = firstPixelLabel(lab, pix)
label = uint16(0);
if isempty(pix), return; end
vals = unique(lab(pix));
vals(vals == 0) = [];
if ~isempty(vals), label = vals(1); end
end

function [track, costsOut, bridgedGaps] = viterbiTrack(candidates, frames, anchor, imageSize, paramout)
T = numel(candidates);
track = zeros(1, T);
costsOut = nan(1, numel(frames));
bridgedGaps = false(numel(frames),1);
maxGap = max(0,round(scalarParam(paramout,'segmentationMaxGapFrames',0)));
dp = cell(1, T);
back = cell(1, T);
backFrame = cell(1,T);
prevFrame = [];
for k = 1:numel(frames)
    f = frames(k);
    cand = candidates{f};
    n = numel(cand);
    if n == 0
        dp{f} = [];
        back{f} = [];
        continue;
    end

    curCost = inf(1, n);
    curBack = zeros(1, n);
    curBackFrame = zeros(1,n);
    for j = 1:n
        if isempty(prevFrame)
            curCost(j) = anchorCost(cand(j), anchor, imageSize, paramout, k);
            continue;
        end
        bestCost = inf;
        bestIdx = 0;
        bestFrame = 0;
        predecessors=prevFrame;
        if maxGap>0
            predecessors=frames(max(1,k-maxGap-1):k-1);
        end
        for previous=predecessors
            prevCand=candidates{previous};prevCost=dp{previous};
            if isempty(prevCost),continue;end
            gap=frames(k)-previous-1;
            if maxGap>0 && (gap>maxGap || gap<0),continue;end
            for iPrev = 1:numel(prevCand)
                if maxGap>0 && gap>0 && ~canBridgeFailure(candidates,frames,previous,f,prevCand(iPrev),cand(j),paramout)
                    continue;
                end
                stepCost = transitionCost(prevCand(iPrev), cand(j), paramout);
                if isinf(stepCost), continue; end
                penalty=0;if maxGap>0,penalty=.25*gap;end
                totalCost = prevCost(iPrev) + stepCost + penalty + anchorCost(cand(j), anchor, imageSize, paramout, k);
                if totalCost < bestCost
                    bestCost = totalCost;
                    bestIdx = iPrev;
                    bestFrame = previous;
                end
            end
        end
        curCost(j) = bestCost;
        curBack(j) = bestIdx;
        curBackFrame(j) = bestFrame;
    end
    if all(isinf(curCost))
        for j = 1:n
            curCost(j) = anchorCost(cand(j), anchor, imageSize, paramout, k) + 10;
        end
    end
    dp{f} = curCost;
    back{f} = curBack;
    backFrame{f} = curBackFrame;
    prevFrame = f;
end

validFrames = frames(~cellfun(@isempty, dp(frames)));
if isempty(validFrames), return; end
lastFrame = validFrames(end);
[~, idx] = min(dp{lastFrame});
if maxGap>0
    f=lastFrame;
    while f>0
        track(f)=idx;costsOut(frames==f)=dp{f}(idx);
        previous=backFrame{f}(idx);nextIdx=back{f}(idx);
        if previous>0
            between=find(frames>previous & frames<f);
            bridgedGaps(between)=true;
        else
            % Preserve the existing independent-segment restart behavior.
            earlier=validFrames(validFrames<f);
            if isempty(earlier),break;end
            previous=earlier(end);[~,nextIdx]=min(dp{previous});
        end
        f=previous;idx=nextIdx;
    end
    return;
end
for k = numel(validFrames):-1:1
    f = validFrames(k);
    track(f) = idx;
    costsOut(frames == f) = dp{f}(idx);
    idx = back{f}(idx);
    if idx <= 0 && k > 1
        prevF = validFrames(k-1);
        [~, idx] = min(dp{prevF});
    end
end
end

function ok=canBridgeFailure(candidates,frames,previous,current,a,b,p)
ok=false;
between=frames(frames>previous & frames<current);
if numel(between)~=current-previous-1,return;end
recovery=scalarParam(p,'segmentationRecoveryAreaRatio',.8);
drop=scalarParam(p,'segmentationGapAreaRatio',.65);
overlap=numel(intersect(a.PixelIdxList,b.PixelIdxList))/max(1,min(a.Area,b.Area));
if b.Area<recovery*a.Area || overlap<.5,return;end
for f=between
    for c=candidates{f}
        overlap=numel(intersect(a.PixelIdxList,c.PixelIdxList))/max(1,min(a.Area,c.Area));
        if c.Area>=drop*a.Area && overlap>=.5,return;end
    end
end
ok=true;
end

function cost = anchorCost(cand, anchor, imageSize, paramout, frameOrdinal)
anchorFrames = max(0, round(scalarParam(paramout, 'anchorFrames', 4)));
if frameOrdinal > anchorFrames
    cost = 0;
    return;
end
xy = cand.Centroid ./ [imageSize(2), imageSize(1)];
d = hypot(xy(1) - anchor(1), xy(2) - anchor(2));
cost = scalarParam(paramout, 'anchorWeight', 2) * d;
end

function cost = transitionCost(a, b, paramout)
diam = max(1, sqrt(double(a.Area)) * 2 / sqrt(pi));
dist = hypot(a.Centroid(1) - b.Centroid(1), a.Centroid(2) - b.Centroid(2)) / diam;
if dist > scalarParam(paramout, 'maxJumpCellDiameters', 2.5)
    cost = inf;
    return;
end
areaCost = abs(log(max(1, double(b.Area)) / max(1, double(a.Area))));
iou = maskIoU(a.PixelIdxList, b.PixelIdxList);
cost = scalarParam(paramout, 'distanceWeight', 1) * dist + ...
    scalarParam(paramout, 'areaWeight', 0.8) * areaCost + ...
    scalarParam(paramout, 'iouWeight', 0.6) * (1 - iou);
end

function val = maskIoU(pixA, pixB)
if isempty(pixA) || isempty(pixB)
    val = 0;
    return;
end
inter = numel(intersect(pixA, pixB));
uni = numel(union(pixA, pixB));
if uni == 0, val = 0; else, val = inter / uni; end
end

function [track, rejected] = rejectTransientSegmentation(candidates, track, frames, paramout)
% Mark short, recoverable failures as missing observations, never as masks
% copied from another frame. The original segmentation remains untouched.
rejected = false(numel(frames),1);
maxGap = max(0, round(scalarParam(paramout,'segmentationMaxGapFrames',0)));
if maxGap == 0, return; end
dropRatio = scalarParam(paramout,'segmentationGapAreaRatio',0.65);
recoveryRatio = scalarParam(paramout,'segmentationRecoveryAreaRatio',0.8);
if ~(dropRatio > 0 && dropRatio < recoveryRatio && recoveryRatio <= 1)
    error('detectViterbiPombeDivisionFrame:GapParameters', ...
        'Require 0 < segmentationGapAreaRatio < segmentationRecoveryAreaRatio <= 1.');
end
k = 2;
while k <= numel(frames)
    prevFrame = frames(k-1); prevIdx = track(prevFrame);
    if prevIdx <= 0, k=k+1; continue; end
    prev = candidates{prevFrame}(prevIdx);
    curIdx = track(frames(k));
    if curIdx > 0 && candidates{frames(k)}(curIdx).Area >= dropRatio*prev.Area
        k=k+1; continue;
    end
    recovered = 0;
    for j=k+1:min(numel(frames),k+maxGap)
        % Tolerance counts acquired frames, not gaps in a sparse selection.
        if frames(j)-prevFrame ~= j-k+1, break; end
        idx = track(frames(j));
        if idx <= 0, continue; end
        next = candidates{frames(j)}(idx);
        overlap = numel(intersect(prev.PixelIdxList,next.PixelIdxList)) / ...
            max(1,min(prev.Area,next.Area));
        if next.Area >= recoveryRatio*prev.Area && overlap >= 0.5
            recovered=j; break;
        end
    end
    if recovered > 0
        rejected(k:recovered-1)=true;
        track(frames(k:recovered-1))=0;
        k=recovered;
    else
        k=k+1;
    end
end
end

function [stopFrame, splitFrame, splitScore, confirmedFrame] = detectSplitStop(candidates, track, frames, paramout)
stopFrame = [];
splitFrame = [];
splitScore = 0;
confirmedFrame = [];
confirmation = max(1,round(scalarParam(paramout,'splitConfirmationFrames',1)));
areas = nan(1, numel(frames));
for k = 1:numel(frames)
    f = frames(k);
    idx = track(f);
    if idx > 0 && idx <= numel(candidates{f})
        areas(k) = double(candidates{f}(idx).Area);
    end
end
validAreas = areas(~isnan(areas) & areas > 0);
if numel(validAreas) < 2, return; end
earlyN = min(5, numel(validAreas));
typicalArea = median(validAreas(1:earlyN));
minTrackFrames = max(1, round(scalarParam(paramout, 'minTrackFrames', 3)));

for k = max(2, minTrackFrames):numel(frames)
    fPrev = frames(k-1);
    f = frames(k);
    idxPrev = track(fPrev);
    idx = track(f);
    if idxPrev <= 0 || idx > numel(candidates{f}) || idx <= 0
        continue;
    end
    prev = candidates{fPrev}(idxPrev);
    cur = candidates{f}(idx);
    dropPrev = double(cur.Area) / max(1, double(prev.Area));
    dropTypical = double(cur.Area) / max(1, typicalArea);
    hasSplit = splitEvidence(prev, candidates{f}, paramout);
    if dropPrev < scalarParam(paramout, 'splitAreaDropRatio', 0.65) && hasSplit > 0
        if ~confirmAreaLoss(candidates,track,frames,k,prev,paramout,confirmation,typicalArea,false)
            continue;
        end
        stopFrame = fPrev;
        splitFrame = f;
        splitScore = hasSplit;
        confirmedFrame = frames(k+confirmation-1);
        return;
    end
    if dropTypical < scalarParam(paramout, 'hardAreaDropRatio', 0.45)
        if ~confirmAreaLoss(candidates,track,frames,k,prev,paramout,confirmation,typicalArea,true)
            continue;
        end
        stopFrame = fPrev;
        splitFrame = f;
        splitScore = max(hasSplit, 0.5);
        confirmedFrame = frames(k+confirmation-1);
        return;
    end
end
end

function ok = confirmAreaLoss(candidates,track,frames,k,prev,p,count,typicalArea,hard)
ok=false;
last=k+count-1;
if last > numel(frames), return; end
for j=k:last
    if frames(j)-frames(k) ~= j-k, return; end
    idx=track(frames(j));
    if idx<=0, return; end
    cur=candidates{frames(j)}(idx);
    if hard
        if cur.Area >= scalarParam(p,'hardAreaDropRatio',0.45)*typicalArea, return; end
    else
        if cur.Area >= scalarParam(p,'splitAreaDropRatio',0.65)*prev.Area || ...
                splitEvidence(prev,candidates{frames(j)},p)<=0, return; end
    end
end
ok=true;
end

function [profileDs,scoreDs] = addToleranceDiagnostics(profileDs,scoreDs,p,rejected,confirmed)
if scalarParam(p,'segmentationMaxGapFrames',0)<=0 && scalarParam(p,'splitConfirmationFrames',1)<=1
    return;
end
scoreDs.data.segmentationGapRejected=logical(rejected(:));
value=NaN; if ~isempty(confirmed), value=confirmed; end
scoreDs.data.splitConfirmedFrame=repmat(value,height(scoreDs.data),1);
settings=struct('maxGapFrames',scalarParam(p,'segmentationMaxGapFrames',0), ...
    'gapAreaRatio',scalarParam(p,'segmentationGapAreaRatio',0.65), ...
    'recoveryAreaRatio',scalarParam(p,'segmentationRecoveryAreaRatio',0.8), ...
    'splitConfirmationFrames',scalarParam(p,'splitConfirmationFrames',1));
profileDs.userData.trackingTolerance=settings;
scoreDs.userData.trackingTolerance=settings;
end

function score = splitEvidence(prev, candNow, paramout)
score = 0;
if numel(candNow) < 2, return; end
diam = max(1, sqrt(double(prev.Area)) * 2 / sqrt(pi));
radius = scalarParam(paramout, 'splitRadiusCellDiameters', 2.2) * diam;
d = arrayfun(@(c) hypot(c.Centroid(1) - prev.Centroid(1), c.Centroid(2) - prev.Centroid(2)), candNow);
near = find(d <= radius);
if numel(near) < 2, return; end
areas = double([candNow(near).Area]);
[~, ord] = sort(areas, 'descend');
pick = near(ord(1:2));
combined = sum(double([candNow(pick).Area]));
ratio = combined / max(1, double(prev.Area));
minRatio = scalarParam(paramout, 'splitCombinedAreaMinRatio', 0.65);
maxRatio = scalarParam(paramout, 'splitCombinedAreaMaxRatio', 1.35);
if ratio >= minRatio && ratio <= maxRatio
    score = 1 - min(abs(log(ratio)), 1);
end
end

function [profileMatrix, septumScore, septumPosition, diagnostics] = computeProfilesAndScores(rawStack, outMask, frames, paramout)
nBins = max(10, round(scalarParam(paramout, 'profileBins', 100)));
profileMatrix = nan(numel(frames), nBins);
septumScore = nan(numel(frames), 1);
septumPosition = nan(numel(frames), 1);
diagnostics = emptySeptumDiagnostics(numel(frames));
method = septumMethod(paramout);

for k = 1:numel(frames)
    f = frames(k);
    mask = outMask(:, :, 1, f) > 0;
    raw = double(rawStack(:, :, 1, f));
    if ~any(mask(:))
        continue;
    end
    prof = longitudinalProfile(raw, mask, nBins);
    profNorm = normalizeProfile(prof);
    profileMatrix(k, :) = profNorm;
    [profileScore, profilePosition] = septumScoreFromProfile(profNorm, paramout);
    diagnostics.profileScore(k) = profileScore;
    if strcmp(method,'transverse2d')
        [septumScore(k), septumPosition(k), info] = ...
            detectViterbiPombeDivisionFrame.scoreTransverseSeptum(raw,mask,paramout);
        diagnostics.coverage(k) = info.coverage;
        diagnostics.angle(k) = info.angle;
        diagnostics.flankOffset(k) = info.flankOffset;
        diagnostics.noiseScale(k) = info.noiseScale;
        diagnostics.endpoints(k,:) = reshape(info.lineEndpoints.',1,4);
    else
        septumScore(k) = profileScore;
        septumPosition(k) = profilePosition;
    end
end
end

function diagnostics = emptySeptumDiagnostics(n)
diagnostics = struct('profileScore',nan(n,1),'coverage',nan(n,1), ...
    'angle',nan(n,1),'flankOffset',nan(n,1),'noiseScale',nan(n,1),'endpoints',nan(n,4));
end

function method = septumMethod(param)
method = 'profile';
if isfield(param,'septumMethod') && ~isempty(param.septumMethod)
    method = lower(readChoiceLocal(param.septumMethod));
end
if ~any(strcmp(method,{'profile','transverse2d'}))
    error('detectViterbiPombeDivisionFrame:SeptumMethod', ...
        'Unknown septum method "%s". Choose profile or transverse2d.',method);
end
end

function prof = longitudinalProfile(raw, mask, nBins)
[yy, xx] = find(mask);
vals = raw(mask);
if numel(vals) < 3
    prof = nan(1, nBins);
    return;
end
coords = [double(xx), double(yy)];
center = mean(coords, 1);
X = coords - center;
[~, ~, V] = svd(X, 'econ');
axisLong = V(:, 1);
s = X * axisLong;
sMin = min(s);
sMax = max(s);
if sMax <= sMin
    prof = nan(1, nBins);
    return;
end
bin = 1 + floor((s - sMin) / (sMax - sMin + eps) * nBins);
bin = max(1, min(nBins, bin));
prof = accumarray(bin, vals, [nBins 1], @mean, NaN).';
x = 1:nBins;
ok = ~isnan(prof);
if nnz(ok) >= 2
    prof = interp1(x(ok), prof(ok), x, 'linear', 'extrap');
end
end

function profNorm = normalizeProfile(prof)
profNorm = prof;
ok = ~isnan(prof);
if nnz(ok) < 3
    return;
end
med = median(prof(ok));
q = prctile(prof(ok), [25 75]);
scale = q(2) - q(1);
if scale <= 0 || isnan(scale)
    scale = std(prof(ok));
end
if scale <= 0 || isnan(scale)
    scale = 1;
end
profNorm = (prof - med) ./ scale;
end

function [score, pos] = septumScoreFromProfile(prof, paramout)
score = NaN;
pos = NaN;
if all(isnan(prof)), return; end
smoothBins = max(1, round(scalarParam(paramout, 'profileSmoothBins', 3)));
if smoothBins > 1
    prof = movmean(prof, smoothBins, 'omitnan');
end
n = numel(prof);
edge = max(0, min(0.45, scalarParam(paramout, 'profileEdgeIgnoreFraction', 0.12)));
idx0 = max(1, floor(edge * n) + 1);
idx1 = min(n, ceil((1 - edge) * n));
if idx1 < idx0, return; end
roi = prof(idx0:idx1);
pol = lower(readChoiceLocal(paramout.septumPolarity));
switch pol
    case 'bright'
        signal = roi;
    case 'absolute'
        signal = abs(roi);
    otherwise
        signal = -roi;
end
[score, localIdx] = max(signal);
pos = (idx0 + localIdx - 2) / max(1, n - 1);
end

function [profileDs, scoreDs, paramout] = buildEmptyDataseries(paramout, roiobj, frames)
nBins = max(10, round(scalarParam(paramout, 'profileBins', 100)));
profileMatrix = nan(numel(frames), nBins);
septumScore = nan(numel(frames), 1);
septumPosition = nan(numel(frames), 1);
trackArea = nan(numel(frames), 1);
trackValid = false(numel(frames), 1);
[profileDs, scoreDs] = buildDataseries(paramout, roiobj, frames, profileMatrix, ...
    septumScore, septumPosition, trackArea, trackValid, [], [], 0);
end

function [profileDs, scoreDs] = buildDataseries(paramout, roiobj, frames, profileMatrix, septumScore, septumPosition, trackArea, trackValid, stopFrame, splitFrame, splitScore, diagnostics)
if nargin < 12, diagnostics = emptySeptumDiagnostics(numel(frames)); end
method = septumMethod(paramout);
nBins = size(profileMatrix, 2);
varNames = arrayfun(@(i) sprintf('p%03d', i), 1:nBins, 'UniformOutput', false);
profileTable = array2table(profileMatrix, 'VariableNames', varNames);
profileDs = dataseries(profileTable, {}, 'class', 'processing', 'type', 'temporal', ...
    'groupid', char(string(paramout.profileSeriesName)), 'parentid', safeRoiId(roiobj));
profileDs.description = 'Normalized longitudinal intensity profile of the Viterbi-selected pombe cell';
profileDs.userData = struct('frames', frames, 'bins', nBins, ...
    'inputInstanceChannel', readChoiceLocal(paramout.instanceChannelName), ...
    'inputRawChannel', readChoiceLocal(paramout.rawChannelName), ...
    'outputMaskChannel', char(string(paramout.outputMaskChannelName)), ...
    'septumScoreThreshold', scalarParam(paramout, 'septumScoreThreshold', 1.5), ...
    'septumMethod',method);
runtime = struct('pluginVersion','unknown','method',method, ...
    'processPath',which('detectViterbiPombeDivisionFrame.process'), ...
    'corePath',mfilename('fullpath'), ...
    'detectorPath',which('detectViterbiPombeDivisionFrame.scoreTransverseSeptum'));
try
    metadata = jsondecode(fileread(fullfile(fileparts(mfilename('fullpath')),'plugin.json')));
    runtime.pluginVersion = char(string(metadata.version));
catch
end
profileDs.userData.processorRuntime = runtime;
if strcmp(method,'transverse2d')
    profileDs.userData.septumDetector = struct( ...
        'version','transverse2d.v1', ...
        'edgeFraction',scalarParam(paramout,'septumLineEdgeFraction',0.2), ...
        'minCoverage',scalarParam(paramout,'septumLineMinCoverage',0.65), ...
        'maxAngle',scalarParam(paramout,'septumLineMaxAngle',30), ...
        'minAspectRatio',scalarParam(paramout,'septumMinAspectRatio',1.3));
    if isfield(paramout,'septumLineFlankOffsets')
        profileDs.userData.septumDetector.flankOffsets = paramout.septumLineFlankOffsets;
    else
        profileDs.userData.septumDetector.flankOffsets = [3 5 7];
    end
end

splitFrameCol = nan(numel(frames), 1);
if ~isempty(splitFrame)
    splitFrameCol(:) = splitFrame;
end
stopFrameCol = nan(numel(frames), 1);
if ~isempty(stopFrame)
    stopFrameCol(:) = stopFrame;
end
threshold = scalarParam(paramout, 'septumScoreThreshold', 1.5);
septumDetected = septumScore(:) >= threshold & logical(trackValid(:));
scoreTable = table(frames(:), septumScore(:), septumPosition(:), trackArea(:), ...
    logical(trackValid(:)), septumDetected(:), stopFrameCol, splitFrameCol, repmat(splitScore, numel(frames), 1), ...
    'VariableNames', {'frame','septumScore','septumPosition','trackArea','trackValid','septumDetected','stopFrame','splitFrameCandidate','splitScore'});
if strcmp(method,'transverse2d')
    extra = array2table([diagnostics.profileScore,diagnostics.coverage, ...
        diagnostics.angle,diagnostics.flankOffset,diagnostics.noiseScale,diagnostics.endpoints], ...
        'VariableNames',{'septumProfileScore','septumLineCoverage','septumLineAngle', ...
        'septumLineFlankOffset','septumNoiseScale','septumLineX1','septumLineY1','septumLineX2','septumLineY2'});
    scoreTable = [scoreTable extra];
end
scoreDs = dataseries(scoreTable, {}, 'class', 'processing', 'type', 'temporal', ...
    'groupid', char(string(paramout.scoreSeriesName)), 'parentid', safeRoiId(roiobj));
scoreDs.description = ['Frame-wise septum score using ' method];
scoreDs.userData = profileDs.userData;
end

function dataout = upsertDataseries(existingData, newSeries)
dataout = existingData;
if isempty(dataout)
    dataout = dataseries.empty;
end
if ~isa(dataout, 'dataseries')
    dataout = dataseries.empty;
end
for i = 1:numel(newSeries)
    gid = char(string(newSeries(i).groupid));
    keep = true(1, numel(dataout));
    for j = 1:numel(dataout)
        try
            keep(j) = ~strcmp(char(string(dataout(j).groupid)), gid);
        catch
            keep(j) = true;
        end
    end
    dataout = [dataout(keep), newSeries(i)];
end
end

function anchor = resolveAnchor(paramout)
mode = lower(readChoiceLocal(paramout.anchorMode));
switch mode
    case 'right'
        anchor = [0.70, 0.55];
    case 'left'
        anchor = [0.30, 0.55];
    case 'up'
        anchor = [0.50, 0.30];
    case 'down'
        anchor = [0.50, 0.70];
    case 'center'
        anchor = [0.50, 0.55];
    case 'custom'
        anchor = [scalarParam(paramout, 'anchorX', 0.70), scalarParam(paramout, 'anchorY', 0.55)];
    otherwise
        anchor = [0.70, 0.55];
end
anchor = max(0, min(1, anchor));
end

function v = readChoiceLocal(val)
if iscell(val)
    if isempty(val)
        v = '';
    else
        v = char(string(val{end}));
    end
else
    v = char(string(val));
end
v = strtrim(v);
if strcmpi(v, 'N/A') || strcmpi(v, 'none')
    v = '';
end
end

function v = scalarParam(s, fieldName, defaultValue)
v = defaultValue;
try
    if isfield(s, fieldName) && ~isempty(s.(fieldName))
        raw = s.(fieldName);
        if iscell(raw), raw = raw{end}; end
        v = double(raw);
    end
catch
    v = defaultValue;
end
if isempty(v) || ~isscalar(v) || isnan(v)
    v = defaultValue;
end
end

function roiId = safeRoiId(roiobj)
roiId = '';
try
    roiId = char(string(roiobj.id));
catch
end
end
