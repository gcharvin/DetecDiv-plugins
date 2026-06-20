function [paramout, dataout, imageout] = core(paramout, roiobj, ctx)
% detecdivPomegranate.core  Pomegranate-like 3D reconstruction and cytometry.

imageout = [];
if nargin < 3 || isempty(ctx) || ~isstruct(ctx)
    ctx = struct();
end
if isempty(roiobj.image)
    roiobj.load('Silent');
end
if isempty(roiobj.image)
    error('detecdivPomegranate:NoImage', 'ROI image is empty; run roiExtract first.');
end

maskName = nonemptyChar(paramout.cellMaskChannelName, 'cell_of_interest');
maskID = roiobj.findChannelID(maskName, 'exact');
if isempty(maskID)
    error('detecdivPomegranate:MaskChannelNotFound', ...
        'Cell mask channel "%s" not found in ROI.', maskName);
end
maskID = maskID(1);

zNames = resolveZStackChannels(paramout, roiobj, maskName);
zIDs = resolveChannelIDs(roiobj, zNames);
if isempty(zIDs)
    error('detecdivPomegranate:NoZStackChannels', 'No z-stack channels selected.');
end

maskStack = roiobj.image(:, :, maskID, :);
zStack = roiobj.image(:, :, zIDs, :);
[H, W, nZ, T] = size(zStack);
frame = selectMeasurementFrame(paramout, roiobj, maskStack, T);
frame = max(1, min(T, round(frame)));

midSlice = selectMidSlice(paramout, roiobj, frame, nZ);
midMaskRaw = squeeze(maskStack(:, :, 1, frame)) > 0;
midMask = cleanMidMask(midMaskRaw, paramout);
if ~any(midMask(:))
    warning('detecdivPomegranate:EmptyMask', ...
        'Selected cell mask is empty at frame %d. Output cell_information is marked invalid.', frame);
end

recon = reconstructPomegranateMask(midMask, nZ, midSlice, paramout);
midRaw = double(zStack(:, :, midSlice, frame));
stackFrame = double(zStack(:, :, :, frame));
measurement = measureReconstruction(midRaw, stackFrame, midMask, recon, midSlice, frame, zNames, paramout);
measurement.source = struct( ...
    'roiId', safeRoiId(roiobj), ...
    'maskChannel', maskName, ...
    'zStackChannels', {zNames}, ...
    'scoreSeries', nonemptyChar(paramout.scoreSeriesName, 'pombe_division_score'), ...
    'focusSeries', nonemptyChar(paramout.focusSeriesName, 'DIC_focus_best_z'));
measurement.qc = buildQc(midRaw, midMask, recon(:, :, midSlice), measurement);
measurement.pomegranateResults = buildPomegranateResultsTable(measurement, stackFrame, recon, frame, midSlice, paramout);
measurement.files = writePomegranateArtifacts(measurement.pomegranateResults, paramout, roiobj, ctx);
measurement.files.qc = writeQcArtifacts(measurement, paramout, roiobj, recon);
if logicalParam(paramout, 'storeReconstructionMask', true)
    measurement.reconstructionMask = recon;
else
    measurement.reconstructionMask = [];
end

cellInfoDs = buildCellInformationDataseries(paramout, roiobj, measurement);
dataout = upsertDataseries(roiobj.data, cellInfoDs);
roiobj.data = dataout;
imageout = [];

paramout.measurementFrame = frame;
paramout.midSlice = midSlice;
paramout.zStackChannelNamesResolved = zNames;
paramout.outputDataSeriesName = char(string(paramout.cellInformationSeriesName));
paramout.outputDirResolved = measurement.files.outputDir;
paramout.resultsCsvPath = measurement.files.csvPath;
paramout.resultsWorkbookPath = measurement.files.workbookPath;
paramout.saveChannels = {};

if logicalParam(paramout, 'debug', false)
    fprintf('[detecdivPomegranate] ROI %s frame=%d z=%d volume=%.3f um3 output=%s\n', ...
        safeRoiId(roiobj), frame, midSlice, measurement.volume_um3, ...
        char(string(paramout.cellInformationSeriesName)));
end
end

function zNames = resolveZStackChannels(paramout, roiobj, maskName)
zNames = normalizeChannelSet(paramout.zStackChannelNames);
availableNames = cellstr(string(roiobj.display.channel(:)'));
availableNames = availableNames(~cellfun(@isempty, availableNames));
zNames = expandZStackChannelPatterns(zNames, availableNames);
if isempty(zNames) || isAllSelector(zNames)
    zNames = availableNames;
    drop = false(1, numel(zNames));
    for i = 1:numel(zNames)
        nm = lower(char(string(zNames{i})));
        drop(i) = strcmpi(zNames{i}, maskName) || startsWith(nm, 'results_') || ...
            contains(nm, 'prob') || contains(nm, 'mask') || contains(nm, 'cell_of_interest') || ...
            contains(nm, 'focus');
    end
    zNames = zNames(~drop);
end
zNames = sortZChannels(zNames);
end

function idx = resolveChannelIDs(roiobj, names)
idx = [];
for i = 1:numel(names)
    one = roiobj.findChannelID(names{i}, 'exact');
    if isempty(one), continue; end
    idx(end+1) = one(1); %#ok<AGROW>
end
idx = unique(idx, 'stable');
end

function frame = selectMeasurementFrame(paramout, roiobj, maskStack, T)
mode = lower(readChoiceLocal(paramout.frameSelectionMode));
scoreDs = findDataseries(roiobj.data, nonemptyChar(paramout.scoreSeriesName, 'pombe_division_score'));
frame = NaN;
if strcmp(mode, 'manual_frame')
    frame = scalarParam(paramout, 'manualFrame', 1);
elseif ~isempty(scoreDs) && istable(scoreDs.data) && height(scoreDs.data) > 0
    tbl = scoreDs.data;
    frames = tableColumn(tbl, 'frame', (1:height(tbl))');
    switch mode
        case 'max_valid_score'
            scores = tableColumn(tbl, 'septumScore', nan(height(tbl), 1));
            trackValid = tableColumn(tbl, 'trackValid', true(height(tbl), 1));
            valid = isfinite(scores) & logical(trackValid(:));
            if any(valid)
                [~, ii] = max(scores(valid));
                jj = find(valid);
                frame = frames(jj(ii));
            end
        case 'max_score'
            scores = tableColumn(tbl, 'septumScore', nan(height(tbl), 1));
            valid = isfinite(scores);
            if any(valid)
                [~, ii] = max(scores(valid));
                jj = find(valid);
                frame = frames(jj(ii));
            end
        case 'split_stop'
            stopFrame = tableColumn(tbl, 'stopFrame', nan(height(tbl), 1));
            validStop = isfinite(stopFrame);
            if any(validStop)
                frame = stopFrame(find(validStop, 1, 'first'));
            else
                splitFrame = tableColumn(tbl, 'splitFrameCandidate', nan(height(tbl), 1));
                validSplit = isfinite(splitFrame);
                if any(validSplit)
                    frame = splitFrame(find(validSplit, 1, 'first')) - 1;
                end
            end
        otherwise
            detected = tableColumn(tbl, 'septumDetected', false(height(tbl), 1));
            valid = logical(detected(:));
            if any(valid)
                frame = frames(find(valid, 1, 'first'));
            end
    end
end
if ~isfinite(frame)
    frame = firstValidMaskFrame(maskStack);
end
if ~isfinite(frame)
    frame = 1;
end
frame = max(1, min(T, round(frame)));
end

function frame = firstValidMaskFrame(maskStack)
frame = NaN;
for f = 1:size(maskStack, 4)
    if any(maskStack(:, :, 1, f) > 0, 'all')
        frame = f;
        return;
    end
end
end

function midSlice = selectMidSlice(paramout, roiobj, frame, nZ)
midSlice = NaN;
focusName = nonemptyChar(paramout.focusSeriesName, 'DIC_focus_best_z');
focusDs = findDataseries(roiobj.data, focusName);
if ~isempty(focusDs) && istable(focusDs.data) && height(focusDs.data) > 0
    tbl = focusDs.data;
    frames = tableColumn(tbl, 'frame', (1:height(tbl))');
    zBest = tableColumn(tbl, 'zBest', nan(height(tbl), 1));
    idx = find(round(double(frames(:))) == round(double(frame)), 1, 'first');
    if ~isempty(idx) && isfinite(double(zBest(idx)))
        midSlice = double(zBest(idx));
    end
end
if ~isfinite(midSlice)
    midSlice = ceil(nZ / 2);
end
midSlice = max(1, min(nZ, round(midSlice)));
end

function mask = cleanMidMask(mask, paramout)
mask = logical(mask);
if ~any(mask(:)), return; end
mask = imfill(mask, 'holes');
closeRadius = max(0, round(scalarParamCompat(paramout, 'pomegranate_gapClosureSizePx', 'maskCloseRadius', 10)));
if closeRadius > 0
    mask = imclose(mask, strel('disk', closeRadius, 0));
    mask = imfill(mask, 'holes');
end
dilateRadius = max(0, round(scalarParamCompat(paramout, 'pomegranate_bandCoverageRadiusPx', 'maskDilateRadius', 0)));
if dilateRadius > 0
    mask = imdilate(mask, strel('disk', dilateRadius, 0));
end
mask = keepLargestComponent(mask);
end

function recon = reconstructPomegranateMask(midMask, nZ, midSlice, paramout)
[H, W] = size(midMask);
recon = false(H, W, nZ);
if ~any(midMask(:)), return; end
distMap = bwdist(~midMask);
skel = medialSkeleton(midMask, paramout);
[sy, sx] = find(skel);
r0 = distMap(skel);
keep = isfinite(r0) & r0 > 0;
sx = sx(keep);
sy = sy(keep);
r0 = r0(keep);

xy = scalarParam(paramout, 'voxelSizeXY', 0.103);
zz = scalarParam(paramout, 'voxelSizeZ', 0.1);
anisotropy = zz / max(xy, eps);
padding = scalarParamCompat(paramout, 'pomegranate_segmentRadiusPaddingPx', 'reconstructionRadiusPaddingPx', 1);
minRadius = scalarParamCompat(paramout, 'pomegranate_minSegmentRadiusPx', 'minSegmentRadiusPx', 1.5);

for z = 1:nZ
    dz = abs(z - midSlice) * anisotropy;
    slice = false(H, W);
    for i = 1:numel(r0)
        rr = sqrt(double(r0(i)).^2 - dz.^2) + padding;
        if ~isfinite(rr) || rr < minRadius
            continue;
        end
        slice = drawDisk(slice, sx(i), sy(i), rr);
    end
    if any(slice(:))
        recon(:, :, z) = imfill(slice, 'holes');
    end
end
end

function skel = medialSkeleton(mask, paramout)
if exist('bwskel', 'file') == 2
    skel = bwskel(mask);
else
    skel = bwmorph(mask, 'skel', Inf);
end
pruneN = max(0, round(scalarParamCompat(paramout, 'pomegranate_skeletonPruneIterations', 'skeletonPruneIterations', 0)));
for i = 1:pruneN
    skel = bwmorph(skel, 'spur', 1);
end
if ~any(skel(:))
    distMap = bwdist(~mask);
    skel = imregionalmax(distMap) & mask;
end
end

function slice = drawDisk(slice, cx, cy, radius)
[H, W] = size(slice);
r = ceil(radius);
x0 = max(1, floor(cx - r));
x1 = min(W, ceil(cx + r));
y0 = max(1, floor(cy - r));
y1 = min(H, ceil(cy + r));
[xx, yy] = meshgrid(x0:x1, y0:y1);
disk = (xx - cx).^2 + (yy - cy).^2 <= radius.^2;
slice(y0:y1, x0:x1) = slice(y0:y1, x0:x1) | disk;
end

function measurement = measureReconstruction(midRaw, stackFrame, midMask, recon, midSlice, frame, zNames, paramout)
xy = scalarParam(paramout, 'voxelSizeXY', 0.103);
zz = scalarParam(paramout, 'voxelSizeZ', 0.1);
voxelVolume = xy * xy * zz;
voxelCount = nnz(recon);
areaBySlicePx = squeeze(sum(sum(recon, 1), 2));
areaBySliceUm2 = double(areaBySlicePx(:)) * xy * xy;
intensityBySliceMean = nan(size(areaBySlicePx(:)));
intensityBySliceSum = nan(size(areaBySlicePx(:)));
for z = 1:size(recon, 3)
    pix = recon(:, :, z);
    if any(pix(:))
        vals = stackFrame(:, :, z);
        vals = vals(pix);
        intensityBySliceMean(z) = mean(vals, 'omitnan');
        intensityBySliceSum(z) = sum(vals, 'omitnan');
    end
end

stats = regionprops(midMask, 'Area', 'Centroid', 'BoundingBox', ...
    'MajorAxisLength', 'MinorAxisLength', 'Orientation', 'Eccentricity', ...
    'Solidity', 'Perimeter', 'ConvexArea', 'PixelIdxList');
if isempty(stats)
    s = emptyStats();
else
    [~, idx] = max([stats.Area]);
    s = stats(idx);
end

midVals = midRaw(midMask);
allVals = stackFrame(recon);
measurement = struct();
measurement.processor = 'detecdivPomegranate';
measurement.valid = any(midMask(:)) && voxelCount > 0;
measurement.frame = frame;
measurement.midSlice = midSlice;
measurement.voxelSizeXY_um = xy;
measurement.voxelSizeZ_um = zz;
measurement.zStackChannelNames = zNames;
measurement.area_mid_px = double(s.Area);
measurement.area_mid_um2 = double(s.Area) * xy * xy;
measurement.volume_voxels = double(voxelCount);
measurement.volume_um3 = double(voxelCount) * voxelVolume;
measurement.centroid_x_px = getVec(s.Centroid, 1);
measurement.centroid_y_px = getVec(s.Centroid, 2);
measurement.majorAxis_px = double(s.MajorAxisLength);
measurement.minorAxis_px = double(s.MinorAxisLength);
measurement.majorAxis_um = double(s.MajorAxisLength) * xy;
measurement.minorAxis_um = double(s.MinorAxisLength) * xy;
measurement.orientation_deg = double(s.Orientation);
measurement.eccentricity = double(s.Eccentricity);
measurement.solidity = double(s.Solidity);
measurement.passesSolidityFilter = measurement.solidity >= scalarParamCompat(paramout, 'pomegranate_solidityThreshold', 'solidityThreshold', 0.9);
measurement.perimeter_px = double(s.Perimeter);
measurement.perimeter_um = double(s.Perimeter) * xy;
measurement.convexArea_px = double(s.ConvexArea);
measurement.areaBySlice_px = double(areaBySlicePx(:));
measurement.areaBySlice_um2 = areaBySliceUm2(:);
measurement.intensity_mid_mean = meanOrNaN(midVals);
measurement.intensity_mid_median = medianOrNaN(midVals);
measurement.intensity_mid_std = stdOrNaN(midVals);
measurement.intensity_mid_sum = sumOrNaN(midVals);
measurement.intensity_3d_mean = meanOrNaN(allVals);
measurement.intensity_3d_median = medianOrNaN(allVals);
measurement.intensity_3d_std = stdOrNaN(allVals);
measurement.intensity_3d_sum = sumOrNaN(allVals);
measurement.intensityBySlice_mean = intensityBySliceMean(:);
measurement.intensityBySlice_sum = intensityBySliceSum(:);
measurement.parameters = rmfieldIfPresent(paramout, 'tip');
end

function tbl = buildPomegranateResultsTable(measurement, stackFrame, recon, frame, midSlice, paramout)
nZ = size(recon, 3);
roiId = string(safeText(measurement.source.roiId, 'ROI'));
experimentName = string(nonemptyChar(paramout.experimentName, ''));
imageName = roiId;
unitName = "um";
rows = cell(nZ, 1);
for z = 1:nZ
    mask = recon(:, :, z);
    im = stackFrame(:, :, z);
    stats = regionprops(mask, im, 'Area', 'MeanIntensity', 'MinIntensity', ...
        'MaxIntensity', 'Centroid', 'WeightedCentroid', 'BoundingBox', ...
        'MajorAxisLength', 'MinorAxisLength', 'Orientation', 'Eccentricity', ...
        'Solidity', 'Perimeter', 'ConvexArea', 'PixelIdxList');
    if isempty(stats)
        s = emptyStats();
        meanVal = NaN; minVal = NaN; maxVal = NaN; stdVal = NaN; medianVal = NaN; modeVal = NaN; sumVal = NaN;
        xpos = ""; ypos = "";
    else
        [~, idx] = max([stats.Area]);
        s = stats(idx);
        vals = double(im(s.PixelIdxList));
        meanVal = meanOrNaN(vals);
        minVal = minOrNaN(vals);
        maxVal = maxOrNaN(vals);
        stdVal = stdOrNaN(vals);
        medianVal = medianOrNaN(vals);
        modeVal = modeOrNaN(vals);
        sumVal = sumOrNaN(vals);
        [xpos, ypos] = boundaryStrings(mask);
    end
    circ = 4 * pi * double(s.Area) / max(double(s.Perimeter).^2, eps);
    ar = double(s.MajorAxisLength) / max(double(s.MinorAxisLength), eps);
    roundness = 4 * double(s.Area) / max(pi * double(s.MajorAxisLength).^2, eps);
    rows{z} = table( ...
        double(s.Area), meanVal, stdVal, modeVal, minVal, ...
        getVec(s.Centroid, 1), getVec(s.Centroid, 2), ...
        getVec(s.WeightedCentroid, 1), getVec(s.WeightedCentroid, 2), ...
        double(s.Perimeter), getVec(s.BoundingBox, 1), getVec(s.BoundingBox, 2), ...
        getVec(s.BoundingBox, 3), getVec(s.BoundingBox, 4), ...
        double(s.MajorAxisLength), double(s.MinorAxisLength), double(s.Orientation), ...
        circ, ar, roundness, double(s.Solidity), ...
        feretApprox(s), NaN, NaN, NaN, double(s.MinorAxisLength), ...
        medianVal, maxVal, sumVal, double(z), ...
        roiId, string(ternary(z == midSlice, 'MID', 'NONMID')), string('WC'), string('Whole_Cell'), ...
        imageName, experimentName, xpos, ypos, ...
        double(measurement.voxelSizeXY_um), double(measurement.voxelSizeXY_um), ...
        double(measurement.voxelSizeZ_um), unitName, double(s.Area), double(frame), ...
        'VariableNames', {'Area','Mean','StdDev','Mode','Min','X','Y','XM','YM', ...
        'Perim','BX','BY','Width','Height','Major','Minor','Angle','Circ','AR', ...
        'Round','Solidity','Feret','FeretX','FeretY','FeretAngle','MinFeret', ...
        'Median','Max','IntDen','Slice','Object_ID','ROI_Type','Nuclear_ID', ...
        'Data_Type','Image','Experiment','xpos','ypos','voxelSize_X', ...
        'voxelSize_Y','voxelSize_Z','voxelSize_unit','Area_px','Frame'});
end
tbl = vertcat(rows{:});
end

function files = writePomegranateArtifacts(tbl, paramout, roiobj, ctx)
outputDir = nonemptyChar(paramout.outputDir, '');
if isempty(outputDir)
    outputDir = outputDirFromContext(ctx);
end
if isempty(outputDir)
    outputDir = pwd;
end
if exist(outputDir, 'dir') ~= 7
    mkdir(outputDir);
end
safeId = matlab.lang.makeValidName(nonemptyChar(safeRoiId(roiobj), 'roi'));
csvPath = '';
workbookPath = '';
if logicalParam(paramout, 'writeCsv', true)
    csvPath = fullfile(outputDir, [safeId '_Results_Full.csv']);
    writetable(tbl, csvPath);
end
if logicalParam(paramout, 'writeExcel', true)
    workbookName = nonemptyChar(paramout.resultsWorkbookName, 'detecdiv_pomegranate_results.xlsx');
    workbookPath = fullfile(outputDir, workbookName);
    try
        writetable(tbl, workbookPath, 'Sheet', sheetName(safeId));
    catch
        writetable(tbl, workbookPath);
    end
end
files = struct('outputDir', outputDir, 'csvPath', csvPath, 'workbookPath', workbookPath);
end

function qcFiles = writeQcArtifacts(measurement, paramout, roiobj, recon)
qcFiles = struct('summaryPng', '', 'overlayPng', '', 'mosaicTilePng', '', 'mosaicPng', '');
writeQc = logicalParam(paramout, 'writeQcImages', true);
writeMosaic = logicalParam(paramout, 'writeMosaicImage', true);
if ~writeQc && ~writeMosaic
    return;
end
roiDir = '';
try
    if isprop(roiobj, 'path') && ~isempty(roiobj.path)
        roiDir = char(string(roiobj.path));
    end
catch
    roiDir = '';
end

safeId = matlab.lang.makeValidName(nonemptyChar(safeRoiId(roiobj), 'roi'));
if writeQc && ~isempty(roiDir) && exist(roiDir, 'dir') == 7
    overlayPath = fullfile(roiDir, [safeId '_pomegranate_qc_overlay.png']);
    summaryPath = fullfile(roiDir, [safeId '_pomegranate_qc_summary.png']);

    try
        imwrite(measurement.qc.overlayMidSliceRgb, overlayPath);
        qcFiles.overlayPng = overlayPath;
    catch ME
        warning('detecdivPomegranate:QcOverlayWriteFailed', ...
            'Could not write QC overlay for ROI "%s": %s', safeId, ME.message);
    end

    try
        rawRgb = repmat(normalizeToUint8(measurement.qc.rawMidSlice), 1, 1, 3);
        reconMidRgb = maskToRgb(measurement.qc.midReconstructionMask, [255 128 0]);
        reconDepthRgb = depthProjectionRgb(measurement, recon);
        summary = tileRgbImages({rawRgb, measurement.qc.overlayMidSliceRgb, reconMidRgb, reconDepthRgb}, 8);
        imwrite(summary, summaryPath);
        qcFiles.summaryPng = summaryPath;
    catch ME
        warning('detecdivPomegranate:QcSummaryWriteFailed', ...
            'Could not write QC summary for ROI "%s": %s', safeId, ME.message);
    end
end

if writeMosaic
    outputDir = '';
    if isfield(measurement, 'files') && isstruct(measurement.files) && ...
            isfield(measurement.files, 'outputDir') && ~isempty(measurement.files.outputDir)
        outputDir = char(string(measurement.files.outputDir));
    end
    if ~isempty(outputDir) && exist(outputDir, 'dir') == 7
        tilePath = fullfile(outputDir, [safeId '_pomegranate_mosaic_tile.png']);
        mosaicName = '';
        if isfield(paramout, 'mosaicFileName') && ~isempty(paramout.mosaicFileName)
            mosaicName = paramout.mosaicFileName;
        end
        mosaicName = nonemptyChar(mosaicName, 'detecdiv_pomegranate_mosaic.png');
        mosaicPath = fullfile(outputDir, mosaicName);
        try
            writeMosaicTile(measurement, tilePath);
            qcFiles.mosaicTilePng = tilePath;
            updateMosaicImage(outputDir, mosaicPath);
            qcFiles.mosaicPng = mosaicPath;
        catch ME
            warning('detecdivPomegranate:MosaicWriteFailed', ...
                'Could not write/update Pomegranate mosaic for ROI "%s": %s', safeId, ME.message);
        end
    end
end
end

function writeMosaicTile(measurement, tilePath)
fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', ...
    'Position', [100 100 560 620]);
cleaner = onCleanup(@() close(fig)); %#ok<NASGU>
ax = axes(fig, 'Units', 'normalized', 'Position', [0.06 0.15 0.88 0.78]);
imagesc(ax, measurement.qc.rawMidSlice);
axis(ax, 'image');
axis(ax, 'off');
colormap(ax, gray(256));
hold(ax, 'on');

plotMaskBoundaries(ax, measurement.qc.midMask, [1 0 0], 1.5);
plotEllipseAndAxes(ax, measurement);
addTileText(fig, measurement);

exportgraphics(fig, tilePath, 'Resolution', 150);
end

function plotMaskBoundaries(ax, mask, color, lineWidth)
if ~any(mask(:))
    return;
end
B = bwboundaries(mask);
for i = 1:numel(B)
    b = B{i};
    plot(ax, b(:,2), b(:,1), 'Color', color, 'LineWidth', lineWidth);
end
end

function plotEllipseAndAxes(ax, measurement)
cx = measurement.centroid_x_px;
cy = measurement.centroid_y_px;
maj = measurement.majorAxis_px;
minr = measurement.minorAxis_px;
if ~all(isfinite([cx cy maj minr measurement.orientation_deg]))
    return;
end
theta = -measurement.orientation_deg * pi / 180;
t = linspace(0, 2*pi, 240);
a = maj / 2;
b = minr / 2;
x = a * cos(t);
y = b * sin(t);
xr = x * cos(theta) - y * sin(theta) + cx;
yr = x * sin(theta) + y * cos(theta) + cy;
plot(ax, xr, yr, 'Color', [0 1 0], 'LineWidth', 1.5);

majorX = [cx - a*cos(theta), cx + a*cos(theta)];
majorY = [cy - a*sin(theta), cy + a*sin(theta)];
minorTheta = theta + pi/2;
minorX = [cx - b*cos(minorTheta), cx + b*cos(minorTheta)];
minorY = [cy - b*sin(minorTheta), cy + b*sin(minorTheta)];
plot(ax, majorX, majorY, 'Color', [0 1 1], 'LineWidth', 1.4);
plot(ax, minorX, minorY, 'Color', [1 0.85 0], 'LineWidth', 1.4);
plot(ax, cx, cy, '+', 'Color', [1 1 1], 'LineWidth', 1.2, 'MarkerSize', 8);
end

function addTileText(fig, measurement)
roiId = safeText(measurement.source.roiId, 'ROI');
titleText = sprintf('%s | frame/time %d | bestZ %d | volume %.0f px^3', ...
    roiId, round(measurement.frame), round(measurement.midSlice), measurement.volume_voxels);
metricText = sprintf(['red: segmented contour   green: ellipse\n' ...
    'cyan: major %.1f px / %.2f um   yellow: minor %.1f px / %.2f um'], ...
    measurement.majorAxis_px, measurement.majorAxis_um, measurement.minorAxis_px, measurement.minorAxis_um);
annotation(fig, 'textbox', [0.04 0.935 0.92 0.045], 'String', titleText, ...
    'Interpreter', 'none', 'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontWeight', 'bold', 'FontSize', 11, 'Color', [0 0 0]);
annotation(fig, 'textbox', [0.04 0.025 0.92 0.095], 'String', metricText, ...
    'Interpreter', 'none', 'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontSize', 8.5, 'Color', [0.05 0.05 0.05]);
end

function updateMosaicImage(outputDir, mosaicPath)
files = dir(fullfile(outputDir, '*_pomegranate_mosaic_tile.png'));
if isempty(files)
    return;
end
[~, ord] = sort({files.name});
files = files(ord);
imgs = cell(1, numel(files));
for i = 1:numel(files)
    imgs{i} = imread(fullfile(files(i).folder, files(i).name));
end
targetH = max(cellfun(@(x) size(x, 1), imgs));
targetW = max(cellfun(@(x) size(x, 2), imgs));
for i = 1:numel(imgs)
    imgs{i} = padOrResizeRgb(imgs{i}, targetH, targetW);
end
n = numel(imgs);
cols = ceil(sqrt(n));
rows = ceil(n / cols);
gap = 12;
canvas = uint8(255 * ones(rows * targetH + (rows - 1) * gap, ...
    cols * targetW + (cols - 1) * gap, 3));
for i = 1:n
    r = floor((i - 1) / cols) + 1;
    c = mod(i - 1, cols) + 1;
    y0 = (r - 1) * (targetH + gap) + 1;
    x0 = (c - 1) * (targetW + gap) + 1;
    canvas(y0:y0+targetH-1, x0:x0+targetW-1, :) = imgs{i};
end
imwrite(canvas, mosaicPath);
end

function rgb = maskToRgb(mask, color)
mask = logical(mask);
rgb = zeros([size(mask), 3], 'uint8');
for c = 1:3
    plane = rgb(:, :, c);
    plane(mask) = uint8(color(c));
    rgb(:, :, c) = plane;
end
end

function rgb = depthProjectionRgb(measurement, recon)
areaBySlice = measurement.areaBySlice_px(:);
nZ = numel(areaBySlice);
if nargin < 2 || isempty(recon)
    if isfield(measurement.qc, 'midReconstructionMask')
        recon = measurement.qc.midReconstructionMask;
    else
        recon = false(1, 1, nZ);
    end
end
if ndims(recon) < 3
    recon = reshape(recon, size(recon, 1), size(recon, 2), 1);
end
[H, W, Z] = size(recon);
rgb = zeros(H, W, 3, 'uint8');
if ~any(recon(:))
    return;
end
depth = zeros(H, W);
cover = false(H, W);
for z = 1:Z
    pix = recon(:, :, z);
    depth(pix) = z;
    cover = cover | pix;
end
if Z <= 1
    hue = zeros(H, W);
else
    hue = (depth - 1) ./ max(1, Z - 1);
end
value = double(cover);
sat = double(cover);
rgbD = hsv2rgb(cat(3, hue, sat, value));
rgb = uint8(round(255 * rgbD));
if isempty(areaBySlice)
    return;
end
end

function out = tileRgbImages(images, gap)
if nargin < 2 || isempty(gap), gap = 6; end
valid = ~cellfun(@isempty, images);
images = images(valid);
if isempty(images)
    out = zeros(1, 1, 3, 'uint8');
    return;
end
H = max(cellfun(@(x) size(x, 1), images));
W = max(cellfun(@(x) size(x, 2), images));
for i = 1:numel(images)
    images{i} = padOrResizeRgb(images{i}, H, W);
end
gapImg = uint8(255 * ones(H, gap, 3));
out = images{1};
for i = 2:numel(images)
    out = cat(2, out, gapImg, images{i}); %#ok<AGROW>
end
end

function rgb = padOrResizeRgb(rgb, H, W)
if size(rgb, 3) == 1
    rgb = repmat(rgb, 1, 1, 3);
end
rgb = uint8(rgb);
h = size(rgb, 1);
w = size(rgb, 2);
canvas = uint8(255 * ones(H, W, 3));
y0 = floor((H - h) / 2) + 1;
x0 = floor((W - w) / 2) + 1;
canvas(y0:y0+h-1, x0:x0+w-1, :) = rgb;
rgb = canvas;
end

function out = outputDirFromContext(ctx)
out = '';
try
    if isfield(ctx, 'run') && isstruct(ctx.run)
        if isfield(ctx.run, 'runPath') && ~isempty(ctx.run.runPath)
            out = char(string(ctx.run.runPath));
        elseif isfield(ctx.run, 'path') && ~isempty(ctx.run.path)
            out = char(string(ctx.run.path));
        end
    end
catch
    out = '';
end
end

function s = emptyStats()
s = struct('Area', 0, 'Centroid', [NaN NaN], 'BoundingBox', [NaN NaN NaN NaN], ...
    'WeightedCentroid', [NaN NaN], ...
    'MajorAxisLength', NaN, 'MinorAxisLength', NaN, 'Orientation', NaN, ...
    'Eccentricity', NaN, 'Solidity', NaN, 'Perimeter', NaN, ...
    'ConvexArea', NaN, 'PixelIdxList', []);
end

function qc = buildQc(midRaw, midMask, midRecon, measurement)
base = normalizeToUint8(midRaw);
rgb = repmat(base, 1, 1, 3);
perim = bwperim(midMask);
reconPerim = bwperim(midRecon);
skel = medialSkeleton(midMask, struct('skeletonPruneIterations', 0));
rgb = paintMask(rgb, reconPerim, [255 128 0]);
rgb = paintMask(rgb, perim, [255 0 0]);
rgb = paintMask(rgb, skel, [0 255 255]);
ellipseMask = ellipsePerimeter(size(midMask), measurement);
rgb = paintMask(rgb, ellipseMask, [0 255 0]);
qc = struct();
qc.overlayMidSliceRgb = rgb;
qc.rawMidSlice = midRaw;
qc.midMask = midMask;
qc.midReconstructionMask = midRecon;
qc.legend = struct('cellContour', 'red', 'reconstructionContour', 'orange', ...
    'medialAxis', 'cyan', 'ellipseFit', 'green');
end

function mask = ellipsePerimeter(sz, measurement)
mask = false(sz);
if ~isfinite(measurement.centroid_x_px) || ~isfinite(measurement.majorAxis_px)
    return;
end
t = linspace(0, 2*pi, 240);
a = measurement.majorAxis_px / 2;
b = measurement.minorAxis_px / 2;
theta = -measurement.orientation_deg * pi / 180;
x = a * cos(t);
y = b * sin(t);
xr = x * cos(theta) - y * sin(theta) + measurement.centroid_x_px;
yr = x * sin(theta) + y * cos(theta) + measurement.centroid_y_px;
idx = round(yr) + (round(xr) - 1) * sz(1);
valid = round(xr) >= 1 & round(xr) <= sz(2) & round(yr) >= 1 & round(yr) <= sz(1);
idx = idx(valid);
mask(idx) = true;
mask = imdilate(mask, strel('disk', 1, 0));
end

function ds = buildCellInformationDataseries(paramout, roiobj, measurement)
tbl = table(double(measurement.frame), double(measurement.midSlice), logical(measurement.valid), ...
    double(measurement.area_mid_um2), double(measurement.volume_um3), ...
    double(measurement.majorAxis_um), double(measurement.minorAxis_um), ...
    double(measurement.solidity), double(measurement.intensity_mid_mean), ...
    double(measurement.intensity_3d_mean), ...
    'VariableNames', {'frame','midSlice','valid','area_mid_um2','volume_um3', ...
    'majorAxis_um','minorAxis_um','solidity','intensity_mid_mean','intensity_3d_mean'});
groupid = char(string(paramout.cellInformationSeriesName));
ds = dataseries(tbl, tbl.Properties.VariableNames, ...
    'groupid', groupid, 'class', 'processing', 'type', 'other', ...
    'parentid', safeRoiId(roiobj));
ds.description = 'Pomegranate-like whole-cell 3D reconstruction and cytometry at septum frame';
ds.userData = measurement;
end

function dataout = upsertDataseries(existingData, newSeries)
dataout = existingData;
if isempty(dataout) || ~isa(dataout, 'dataseries')
    dataout = dataseries.empty;
end
gid = char(string(newSeries.groupid));
keep = true(1, numel(dataout));
for j = 1:numel(dataout)
    try
        keep(j) = ~strcmp(char(string(dataout(j).groupid)), gid);
    catch
        keep(j) = true;
    end
end
dataout = [dataout(keep), newSeries];
end

function ds = findDataseries(data, groupid)
ds = [];
if isempty(data) || ~isa(data, 'dataseries'), return; end
for i = 1:numel(data)
    try
        if strcmp(char(string(data(i).groupid)), groupid)
            ds = data(i);
            return;
        end
    catch
    end
end
end

function col = tableColumn(tbl, name, fallback)
if ismember(name, tbl.Properties.VariableNames)
    col = tbl.(name);
else
    col = fallback;
end
end

function mask = keepLargestComponent(mask)
cc = bwconncomp(mask);
if cc.NumObjects <= 1, return; end
sizes = cellfun(@numel, cc.PixelIdxList);
[~, idx] = max(sizes);
out = false(size(mask));
out(cc.PixelIdxList{idx}) = true;
mask = out;
end

function rgb = paintMask(rgb, mask, color)
for c = 1:3
    plane = rgb(:, :, c);
    plane(mask) = uint8(color(c));
    rgb(:, :, c) = plane;
end
end

function out = normalizeToUint8(im)
im = double(im);
vals = im(isfinite(im));
if isempty(vals)
    out = zeros(size(im), 'uint8');
    return;
end
lo = prctile(vals, 1);
hi = prctile(vals, 99);
if hi <= lo
    hi = max(vals);
    lo = min(vals);
end
if hi <= lo
    out = zeros(size(im), 'uint8');
else
    out = uint8(min(max((im - lo) ./ (hi - lo), 0), 1) * 255);
end
end

function names = normalizeChannelSet(values)
if isempty(values)
    names = {};
elseif ischar(values) || (isstring(values) && isscalar(values))
    txt = char(string(values));
    names = regexp(txt, '[,;]', 'split');
elseif isstring(values)
    names = cellstr(values(:))';
elseif iscell(values)
    names = {};
    for i = 1:numel(values)
        item = values{i};
        if iscell(item)
            names = [names normalizeChannelSet(item)]; %#ok<AGROW>
        elseif ischar(item) || (isstring(item) && isscalar(item))
            names{end+1} = char(string(item)); %#ok<AGROW>
        else
            names = [names cellstr(string(item(:)))']; %#ok<AGROW>
        end
    end
else
    names = {};
end
names = cellfun(@(x) strtrim(char(string(x))), names(:)', 'UniformOutput', false);
names = unique(names(~cellfun(@isempty, names)), 'stable');
end

function names = expandZStackChannelPatterns(values, availableNames)
names = normalizeChannelSet(values);
availableNames = normalizeChannelSet(availableNames);
if isempty(names) || isempty(availableNames)
    return;
end

expanded = {};
for i = 1:numel(names)
    item = strtrim(char(string(names{i})));
    if isZStackChannelPattern(item)
        rx = zStackChannelPatternToRegexp(item);
        matches = {};
        for j = 1:numel(availableNames)
            candidate = char(string(availableNames{j}));
            if ~isempty(regexp(candidate, rx, 'once'))
                matches{end+1} = candidate; %#ok<AGROW>
            end
        end
        if ~isempty(matches)
            expanded = [expanded matches]; %#ok<AGROW>
        else
            expanded{end+1} = item; %#ok<AGROW>
        end
    else
        expanded{end+1} = item; %#ok<AGROW>
    end
end
names = unique(expanded, 'stable');
end

function tf = isZStackChannelPattern(value)
value = strtrim(char(string(value)));
if isempty(value) || any(strcmpi(value, {'all','*',':','<all>','@source','@roi'}))
    tf = false;
    return;
end
tf = contains(value, '$') || contains(value, '#') || contains(value, '*');
end

function rx = zStackChannelPatternToRegexp(pat)
pat = char(string(pat));
rx = '^';
i = 1;
while i <= numel(pat)
    ch = pat(i);
    if ch == '$' || ch == '#'
        j = i;
        while j <= numel(pat) && (pat(j) == '$' || pat(j) == '#')
            j = j + 1;
        end
        rx = [rx '\d{' num2str(j - i) '}']; %#ok<AGROW>
        i = j;
    elseif ch == '*'
        rx = [rx '.*']; %#ok<AGROW>
        i = i + 1;
    else
        rx = [rx regexptranslate('escape', ch)]; %#ok<AGROW>
        i = i + 1;
    end
end
rx = [rx '$'];
end

function tf = isAllSelector(values)
tf = isempty(values) || (numel(values) == 1 && any(strcmpi(values{1}, {'all','*',':','<all>','@source','@roi'})));
end

function out = sortZChannels(channels)
out = channels;
if numel(out) < 2, return; end
z = nan(1, numel(out));
for i = 1:numel(out)
    tok = regexp(char(string(out{i})), '(\d+)$', 'tokens', 'once');
    if ~isempty(tok), z(i) = str2double(tok{1}); end
end
if all(isfinite(z))
    [~, ord] = sort(z);
    out = out(ord);
end
end

function v = readChoiceLocal(val)
if iscell(val)
    if isempty(val), v = ''; else, v = char(string(val{end})); end
else
    v = char(string(val));
end
v = strtrim(v);
if strcmpi(v, 'N/A') || strcmpi(v, 'none'), v = ''; end
end

function value = nonemptyChar(value, fallback)
value = strtrim(char(string(value)));
if isempty(value), value = fallback; end
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

function v = scalarParamCompat(s, preferredName, legacyName, defaultValue)
if isfield(s, preferredName) && ~isempty(s.(preferredName))
    v = scalarParam(s, preferredName, defaultValue);
elseif isfield(s, legacyName) && ~isempty(s.(legacyName))
    v = scalarParam(s, legacyName, defaultValue);
else
    v = defaultValue;
end
end

function tf = logicalParam(s, fieldName, defaultValue)
tf = defaultValue;
try
    if isfield(s, fieldName) && ~isempty(s.(fieldName))
        raw = s.(fieldName);
        if iscell(raw), raw = raw{end}; end
        if ischar(raw) || isstring(raw)
            tf = any(strcmpi(char(string(raw)), {'true','yes','on','1'}));
        else
            tf = logical(raw);
        end
    end
catch
    tf = defaultValue;
end
end

function out = rmfieldIfPresent(s, fieldName)
out = s;
if isfield(out, fieldName), out = rmfield(out, fieldName); end
end

function value = getVec(vec, idx)
value = NaN;
if numel(vec) >= idx, value = double(vec(idx)); end
end

function value = meanOrNaN(vals)
vals = vals(isfinite(vals));
if isempty(vals), value = NaN; else, value = mean(vals); end
end

function value = medianOrNaN(vals)
vals = vals(isfinite(vals));
if isempty(vals), value = NaN; else, value = median(vals); end
end

function value = stdOrNaN(vals)
vals = vals(isfinite(vals));
if numel(vals) < 2, value = NaN; else, value = std(vals, 0); end
end

function value = sumOrNaN(vals)
vals = vals(isfinite(vals));
if isempty(vals), value = NaN; else, value = sum(vals); end
end

function value = minOrNaN(vals)
vals = vals(isfinite(vals));
if isempty(vals), value = NaN; else, value = min(vals); end
end

function value = maxOrNaN(vals)
vals = vals(isfinite(vals));
if isempty(vals), value = NaN; else, value = max(vals); end
end

function value = modeOrNaN(vals)
vals = vals(isfinite(vals));
if isempty(vals), value = NaN; else, value = mode(vals); end
end

function [xpos, ypos] = boundaryStrings(mask)
B = bwboundaries(mask, 'noholes');
if isempty(B)
    xpos = "";
    ypos = "";
    return;
end
[~, idx] = max(cellfun(@(x) size(x, 1), B));
b = B{idx};
xpos = string(strjoin(cellstr(string(b(:, 2)')), ','));
ypos = string(strjoin(cellstr(string(b(:, 1)')), ','));
end

function value = feretApprox(s)
value = double(max(s.MajorAxisLength, s.MinorAxisLength));
if isempty(value) || ~isfinite(value), value = NaN; end
end

function out = ternary(cond, a, b)
if cond, out = a; else, out = b; end
end

function txt = safeText(txt, fallback)
try
    txt = char(string(txt));
catch
    txt = '';
end
if isempty(txt), txt = fallback; end
end

function name = sheetName(raw)
name = char(string(raw));
name = regexprep(name, '[:\\/?*\[\]]', '_');
if isempty(name), name = 'roi'; end
name = name(1:min(31, numel(name)));
end

function id = safeRoiId(roiobj)
id = '';
try
    id = char(string(roiobj.id));
catch
end
end
