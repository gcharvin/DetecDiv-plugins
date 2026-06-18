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

inputMode = readChoiceLocal(paramout.inputMode);
if isempty(inputMode), inputMode = 'auto'; end

candidates = cell(1, T);
for f = frames
    lab = normalizeLabelFrame(maskStack(:, :, 1, f), inputMode);
    candidates{f} = frameCandidates(lab, paramout);
end

if all(cellfun(@isempty, candidates(frames)))
    warning('detectViterbiPombeDivisionFrame:NoCandidates', ...
        'No mask candidates found in "%s". Output will be empty.', instanceName);
    outMask = zeros(H, W, 1, T, 'uint16');
    [profileDs, scoreDs, paramout] = buildEmptyDataseries(paramout, roiobj, frames);
    dataout = upsertDataseries(roiobj.data, [profileDs scoreDs]);
    [paramout, dataout, imageout] = writeOutput(roiobj, paramout, outMask, dataout);
    return;
end

anchor = resolveAnchor(paramout);
[track, costs] = viterbiTrack(candidates, frames, anchor, [H W], paramout);
[stopFrame, splitFrame, splitScore] = detectSplitStop(candidates, track, frames, paramout);

outMask = zeros(H, W, 1, T, 'uint16');
trackArea = nan(numel(frames), 1);
trackValid = false(numel(frames), 1);
for k = 1:numel(frames)
    f = frames(k);
    if paramout.stopAtSplit && ~isempty(stopFrame) && f > stopFrame
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

[profileMatrix, septumScore, septumPosition] = computeProfilesAndScores( ...
    rawStack, outMask, frames, paramout);

[profileDs, scoreDs] = buildDataseries(paramout, roiobj, frames, profileMatrix, ...
    septumScore, septumPosition, trackArea, trackValid, stopFrame, splitFrame, splitScore);

paramout.trackFrames = frames;
paramout.trackCandidateIndex = track(frames);
paramout.viterbiCost = costs;
paramout.stopFrame = stopFrame;
paramout.splitFrameCandidate = splitFrame;
paramout.splitScore = splitScore;
paramout.inputChannelName = instanceName;
paramout.rawChannelNameResolved = rawName;
paramout.saveChannels = {char(string(paramout.outputMaskChannelName))};

if isfield(paramout, 'debug') && paramout.debug
    fprintf('[detectViterbiPombeDivisionFrame] instance="%s" raw="%s" output="%s" stop=%s split=%s\n', ...
        instanceName, rawName, char(string(paramout.outputMaskChannelName)), mat2str(stopFrame), mat2str(splitFrame));
end

dataout = upsertDataseries(roiobj.data, [profileDs scoreDs]);
[paramout, dataout, imageout] = writeOutput(roiobj, paramout, outMask, dataout);
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

function [track, costsOut] = viterbiTrack(candidates, frames, anchor, imageSize, paramout)
T = numel(candidates);
track = zeros(1, T);
costsOut = nan(1, numel(frames));
dp = cell(1, T);
back = cell(1, T);
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
    for j = 1:n
        if isempty(prevFrame)
            curCost(j) = anchorCost(cand(j), anchor, imageSize, paramout, k);
            continue;
        end
        prevCand = candidates{prevFrame};
        prevCost = dp{prevFrame};
        bestCost = inf;
        bestIdx = 0;
        for iPrev = 1:numel(prevCand)
            stepCost = transitionCost(prevCand(iPrev), cand(j), paramout);
            if isinf(stepCost), continue; end
            totalCost = prevCost(iPrev) + stepCost + anchorCost(cand(j), anchor, imageSize, paramout, k);
            if totalCost < bestCost
                bestCost = totalCost;
                bestIdx = iPrev;
            end
        end
        curCost(j) = bestCost;
        curBack(j) = bestIdx;
    end
    if all(isinf(curCost))
        for j = 1:n
            curCost(j) = anchorCost(cand(j), anchor, imageSize, paramout, k) + 10;
        end
    end
    dp{f} = curCost;
    back{f} = curBack;
    prevFrame = f;
end

validFrames = frames(~cellfun(@isempty, dp(frames)));
if isempty(validFrames), return; end
lastFrame = validFrames(end);
[~, idx] = min(dp{lastFrame});
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

function [stopFrame, splitFrame, splitScore] = detectSplitStop(candidates, track, frames, paramout)
stopFrame = [];
splitFrame = [];
splitScore = 0;
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
        stopFrame = fPrev;
        splitFrame = f;
        splitScore = hasSplit;
        return;
    end
    if dropTypical < scalarParam(paramout, 'hardAreaDropRatio', 0.45)
        stopFrame = fPrev;
        splitFrame = f;
        splitScore = max(hasSplit, 0.5);
        return;
    end
end
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

function [profileMatrix, septumScore, septumPosition] = computeProfilesAndScores(rawStack, outMask, frames, paramout)
nBins = max(10, round(scalarParam(paramout, 'profileBins', 100)));
profileMatrix = nan(numel(frames), nBins);
septumScore = nan(numel(frames), 1);
septumPosition = nan(numel(frames), 1);

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
    [septumScore(k), septumPosition(k)] = septumScoreFromProfile(profNorm, paramout);
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

function [profileDs, scoreDs] = buildDataseries(paramout, roiobj, frames, profileMatrix, septumScore, septumPosition, trackArea, trackValid, stopFrame, splitFrame, splitScore)
nBins = size(profileMatrix, 2);
varNames = arrayfun(@(i) sprintf('p%03d', i), 1:nBins, 'UniformOutput', false);
profileTable = array2table(profileMatrix, 'VariableNames', varNames);
profileDs = dataseries(profileTable, {}, 'class', 'processing', 'type', 'temporal', ...
    'groupid', char(string(paramout.profileSeriesName)), 'parentid', safeRoiId(roiobj));
profileDs.description = 'Normalized longitudinal intensity profile of the Viterbi-selected pombe cell';
profileDs.userData = struct('frames', frames, 'bins', nBins, ...
    'inputInstanceChannel', readChoiceLocal(paramout.instanceChannelName), ...
    'inputRawChannel', readChoiceLocal(paramout.rawChannelName), ...
    'outputMaskChannel', char(string(paramout.outputMaskChannelName)));

splitFrameCol = nan(numel(frames), 1);
if ~isempty(splitFrame)
    splitFrameCol(:) = splitFrame;
end
stopFrameCol = nan(numel(frames), 1);
if ~isempty(stopFrame)
    stopFrameCol(:) = stopFrame;
end
scoreTable = table(frames(:), septumScore(:), septumPosition(:), trackArea(:), ...
    logical(trackValid(:)), stopFrameCol, splitFrameCol, repmat(splitScore, numel(frames), 1), ...
    'VariableNames', {'frame','septumScore','septumPosition','trackArea','trackValid','stopFrame','splitFrameCandidate','splitScore'});
scoreDs = dataseries(scoreTable, {}, 'class', 'processing', 'type', 'temporal', ...
    'groupid', char(string(paramout.scoreSeriesName)), 'parentid', safeRoiId(roiobj));
scoreDs.description = 'Frame-wise septum score from normalized pombe cell intensity profile';
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
    case 'left'
        anchor = [0.30, 0.55];
    case 'center'
        anchor = [0.50, 0.55];
    otherwise
        anchor = [scalarParam(paramout, 'anchorX', 0.70), scalarParam(paramout, 'anchorY', 0.55)];
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
