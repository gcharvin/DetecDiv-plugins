function [paramout, dataout, imageout] = core(param, roiobj, ctx)
% bestFocusPlane.core  Compute zBest per ROI and frame, then add one channel.

imageout = [];
dataout = [];

if nargin == 0 || isempty(param)
    paramout = bestFocusPlane.setparam(struct());
    return;
end
if nargin < 3 || isempty(ctx) || ~isstruct(ctx)
    ctx = struct();
end

paramout = normalizeParams(param, ctx);
if isempty(roiobj)
    return;
end

if isempty(roiobj.image)
    roiobj.load('Silent');
end
if isempty(roiobj.image)
    error('bestFocusPlane:NoImage', 'ROI image is empty; run roiExtract first.');
end

channelNames = resolveInputChannels(paramout, roiobj, ctx);
zIdx = resolveChannelIndices(roiobj, channelNames);
if numel(zIdx) < 1
    error('bestFocusPlane:NoChannels', 'No input z-stack channels found in ROI.');
end

frames = resolveFrames(ctx, size(roiobj.image, 4));
stack = roiobj.image(:,:,zIdx,frames);
[focusBlockSubset, focusInfo] = buildBestFocusBlock(stack, paramout);

focusBlock = zeros(size(roiobj.image,1), size(roiobj.image,2), 1, size(roiobj.image,4), class(roiobj.image));
focusBlock(:,:,1,frames) = focusBlockSubset;
focusInfo.frame = frames(:);
focusInfo.localFrame = frames(:);
focusInfo.zBestChannelIndex = zIdx(focusInfo.zBest(:));
focusInfo.zBestChannelIndex = focusInfo.zBestChannelIndex(:);

outputName = char(string(paramout.outputChannelName));
if ~isempty(roiobj.findChannelID(outputName))
    if paramout.overwrite
        roiobj.removeChannel(outputName);
    else
        error('bestFocusPlane:OutputExists', 'Output channel "%s" already exists.', outputName);
    end
end
roiobj.addChannel(focusBlock, outputName, [1 1 1], [1 1 1]);

dataout = roiobj.data;
if isempty(dataout) || ~isa(dataout, 'dataseries')
    dataout = dataseries.empty;
end
dataout = upsertZBestDataseries(dataout, roiobj, paramout, focusInfo, channelNames);
roiobj.data = dataout;

imageout = roiobj.image;
paramout.saveChannels = {outputName};

if paramout.verbose
    fprintf('[bestFocusPlane] ROI %s | z=%d | frames=%d | output=%s\n', ...
        safeRoiId(roiobj), numel(zIdx), numel(frames), outputName);
end
end

function paramout = normalizeParams(param, ctx)
defaults = bestFocusPlane.setparam(ctx);
paramout = mergeStruct(defaults, param);
paramout.outputChannelName = nonemptyChar(paramout.outputChannelName, 'DIC_focus');
paramout.zBestOutputName = nonemptyChar(paramout.zBestOutputName, [paramout.outputChannelName '_best_z']);
paramout.focusSmoothZ = max(1, round(numericScalar(paramout.focusSmoothZ, 5)));
paramout.focusProjectionRadius = max(0, round(numericScalar(paramout.focusProjectionRadius, 0)));
paramout.focusCenterCrop = min(1, max(eps, numericScalar(paramout.focusCenterCrop, 1.0)));
paramout.overwrite = logicalScalar(paramout.overwrite, true);
paramout.verbose = logicalScalar(paramout.verbose, true);
end

function channels = resolveInputChannels(paramout, roiobj, ctx)
channels = normalizeChannelSpec(paramout.channels);
if isempty(channels) && isfield(ctx, 'channels') && ~isempty(ctx.channels)
    channels = normalizeChannelSpec(ctx.channels);
end
if isempty(channels) || isAllSelector(channels)
    channels = {};
    try
        channels = cellstr(string(roiobj.display.channel(:)'));
    catch
        channels = {};
    end
end
channels = channels(~cellfun(@isempty, channels));
channels = unique(channels, 'stable');
channels = setdiff(channels, {char(string(paramout.outputChannelName))}, 'stable');
end

function idx = resolveChannelIndices(roiobj, channelNames)
idx = [];
for i = 1:numel(channelNames)
    one = roiobj.findChannelID(channelNames{i}, 'exact');
    if isempty(one)
        continue;
    end
    if numel(one) ~= 1
        error('bestFocusPlane:MultiPlaneLogicalChannel', ...
            'Input channel "%s" maps to %d planes; expected one plane per z channel.', ...
            channelNames{i}, numel(one));
    end
    idx(end+1) = one; %#ok<AGROW>
end
idx = unique(idx, 'stable');
end

function frames = resolveFrames(ctx, T)
frames = [];
if isfield(ctx, 'frames') && ~isempty(ctx.frames)
    frames = ctx.frames;
elseif isfield(ctx, 'sel') && isstruct(ctx.sel) && isfield(ctx.sel, 'frames') && ~isempty(ctx.sel.frames)
    frames = ctx.sel.frames;
end
if isempty(frames) || isequal(frames, -1)
    frames = 1:T;
else
    frames = round(double(frames(:)'));
    frames = unique(frames(isfinite(frames) & frames >= 1 & frames <= T), 'stable');
    if isempty(frames)
        frames = 1:T;
    end
end
end

function [focusBlock, info] = buildBestFocusBlock(stack, opt)
[H,W,C,T] = size(stack);
focusBlock = zeros(H, W, 1, T, class(stack));
rawScores = zeros(C, T);
smoothScores = zeros(C, T);
zBest = ones(T, 1);
peakScore = zeros(T, 1);
medianScore = zeros(T, 1);
peakRatio = zeros(T, 1);

for it = 1:T
    for iz = 1:C
        rawScores(iz,it) = focusScoreLaplacian(stack(:,:,iz,it), opt.focusCenterCrop);
    end
    smoothScores(:,it) = smoothFocusVector(rawScores(:,it), opt.focusSmoothZ);
    [peakScore(it), zBest(it)] = max(smoothScores(:,it));
    finiteScores = smoothScores(isfinite(smoothScores(:,it)),it);
    if isempty(finiteScores)
        medianScore(it) = NaN;
    else
        medianScore(it) = median(finiteScores);
    end
    peakRatio(it) = peakScore(it) ./ max(abs(medianScore(it)), eps);
    focusBlock(:,:,1,it) = selectFocusedPlane(stack(:,:,:,it), zBest(it), opt.focusProjectionRadius);
end

info = struct();
info.rawScores = rawScores;
info.smoothScores = smoothScores;
info.zBest = zBest;
info.peakScore = peakScore;
info.medianScore = medianScore;
info.peakRatio = peakRatio;
end

function score = focusScoreLaplacian(im, centerCrop)
im = double(centerCropImage(im, centerCrop));
finiteIm = im(isfinite(im));
if isempty(finiteIm)
    score = NaN;
    return;
end
im = im - median(finiteIm);
lap = conv2(im, [0 1 0; 1 -4 1; 0 1 0], 'same');
finiteLap = lap(isfinite(lap));
if isempty(finiteLap)
    score = NaN;
else
    score = var(finiteLap(:), 0);
end
end

function out = centerCropImage(im, frac)
if frac >= 1
    out = im;
    return;
end
[H,W] = size(im);
h = max(1, round(H * frac));
w = max(1, round(W * frac));
r0 = floor((H - h) / 2) + 1;
c0 = floor((W - w) / 2) + 1;
out = im(r0:r0+h-1, c0:c0+w-1);
end

function y = smoothFocusVector(x, win)
x = double(x(:));
if win <= 1 || numel(x) <= 2
    y = x;
    return;
end
win = min(win, numel(x));
try
    y = smoothdata(x, 'movmean', win, 'omitnan');
catch
    kernel = ones(win, 1) ./ win;
    valid = isfinite(x);
    x0 = x;
    x0(~valid) = 0;
    y = conv(x0, kernel, 'same') ./ max(conv(double(valid), kernel, 'same'), eps);
end
end

function plane = selectFocusedPlane(stack, zBest, radius)
C = size(stack, 3);
zBest = min(max(1, round(zBest)), C);
if radius <= 0
    plane = stack(:,:,zBest);
    return;
end
idx = max(1, zBest-radius):min(C, zBest+radius);
avg = mean(double(stack(:,:,idx)), 3);
plane = castImageLike(avg, class(stack));
end

function out = castImageLike(im, className)
if strcmp(className, 'logical')
    out = im > 0;
    return;
end
if isinteger(cast(0, className))
    im = min(max(round(im), double(intmin(className))), double(intmax(className)));
end
out = cast(im, className);
end

function dataout = upsertZBestDataseries(dataout, roiobj, paramout, info, channelNames)
zBestChannelName = string(channelNames(info.zBest(:)));
zBestChannelName = zBestChannelName(:);
rawCurve = num2cell(info.rawScores', 2);
smoothCurve = num2cell(info.smoothScores', 2);
tbl = table( ...
    double(info.frame(:)), ...
    double(info.localFrame(:)), ...
    double(info.zBest(:)), ...
    double(info.zBestChannelIndex(:)), ...
    zBestChannelName, ...
    double(info.peakScore(:)), ...
    double(info.medianScore(:)), ...
    double(info.peakRatio(:)), ...
    rawCurve, ...
    smoothCurve, ...
    'VariableNames', {'frame','localFrame','zBest','zBestChannelIndex','zBestChannelName','focusPeak','focusMedian','focusPeakRatio','focusCurveRaw','focusCurveSmooth'});

groupid = char(string(paramout.zBestOutputName));
series = dataseries(tbl, tbl.Properties.VariableNames, ...
    'groupid', groupid, 'class', 'processing', 'type', 'temporal');
try, series.parentid = roiobj.id; catch, end

if isempty(dataout) || (numel(dataout) == 1 && isempty(dataout(1).groupid) && isempty(dataout(1).data))
    dataout = series;
    return;
end
idx = find(arrayfun(@(x) isprop(x,'groupid') && strcmp(char(string(x.groupid)), groupid), dataout), 1, 'first');
if isempty(idx)
    dataout(end+1) = series;
else
    dataout(idx) = series;
end
end

function out = mergeStruct(base, override)
out = base;
if ~isstruct(override)
    return;
end
names = fieldnames(override);
for i = 1:numel(names)
    out.(names{i}) = override.(names{i});
end
end

function value = nonemptyChar(value, fallback)
value = strtrim(char(string(value)));
if isempty(value)
    value = fallback;
end
end

function value = numericScalar(value, fallback)
try
    value = double(value);
    if ~isscalar(value) || ~isfinite(value)
        value = fallback;
    end
catch
    value = fallback;
end
end

function tf = logicalScalar(value, fallback)
tf = fallback;
try
    if islogical(value)
        tf = any(value(:));
    elseif isnumeric(value)
        tf = any(value(:) ~= 0);
    else
        s = lower(strtrim(char(string(value))));
        if any(strcmp(s, {'true','t','yes','y','on','1'}))
            tf = true;
        elseif any(strcmp(s, {'false','f','no','n','off','0'}))
            tf = false;
        end
    end
catch
    tf = fallback;
end
end

function values = normalizeChannelSpec(values)
if isempty(values)
    values = {};
    return;
end
if ischar(values) || (isstring(values) && isscalar(values))
    s = strtrim(char(string(values)));
    if isempty(s)
        values = {};
    else
        values = {s};
    end
elseif isstring(values)
    values = cellstr(values(:))';
elseif iscell(values)
    values = cellfun(@(x) strtrim(char(string(x))), values(:)', 'UniformOutput', false);
else
    values = {};
end
values = values(~cellfun(@isempty, values));
end

function tf = isAllSelector(values)
tf = false;
if isempty(values)
    return;
end
if numel(values) == 1
    s = lower(strtrim(char(string(values{1}))));
    tf = any(strcmp(s, {'all','*',':','<all>','@source','@roi'}));
end
end

function id = safeRoiId(roiobj)
id = '<roi>';
try
    id = char(string(roiobj.id));
catch
end
end
