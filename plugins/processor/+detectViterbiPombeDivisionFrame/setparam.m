function paramout = setparam(ctx)
% detectViterbiPombeDivisionFrame.setparam  Defaults for pombe division timing.

if nargin < 1
    ctx = struct();
end

listChannels = {};
if isfield(ctx, 'channels')
    listChannels = normalizeChannelList(ctx.channels);
end
if isempty(listChannels)
    try
        listChannels = normalizeChannelList(listAvailableChannels);
    catch
        listChannels = {};
    end
end
if isempty(listChannels)
    listChannels = {''};
end

instancePreferred = choosePreferredInstanceChannel(listChannels);
rawPreferred = choosePreferredRawChannel(listChannels);
choices = [{'none'}, listChannels];

paramout = struct();
tip = {};

% Explicit input bindings.
paramout.instanceChannelName = [choices {instancePreferred}];
tip{end+1} = 'INPUT binding: labeled CellposeSAM instance mask channel';

paramout.rawChannelName = [choices {rawPreferred}];
tip{end+1} = 'INPUT binding: raw/DIC image channel used for septum intensity profile';

paramout.focusQualityEnabled = false;
tip{end+1} = 'Exclude low-focus frames before tracking, split decisions and septum scoring; leave raw and input masks unchanged';
paramout.focusDetailRatioThreshold = .5;
tip{end+1} = 'Reject only when relative fine detail and trap-edge strength both fall below their thresholds';
paramout.focusEdgeRatioThreshold = .92;
tip{end+1} = 'Relative smoothed trap-edge strength, combined with focusDetailRatioThreshold';
paramout.focusMinReferenceFrames = 5;
tip{end+1} = 'Minimum informative frames for the within-movie reference; flat/nonfinite frames are always excluded';
paramout.focusRegions = [.20 .23 .66 .18;.20 .70 .66 .15];
tip{end+1} = 'Normalized [x y width height] rectangles on stable trap walls; calibrate for different ROI crops';

paramout.septumBoundarySupportEnabled = false;
tip{end+1} = 'At a recent split, score the interface of two observed daughter masks supported by their previous mother; abstain if a half is missing. Preserve the selected target mask.';

% Explicit output bindings.
paramout.outputMaskChannelName = 'cell_of_interest';
tip{end+1} = 'OUTPUT binding: binary mask channel for the tracked cell of interest';

paramout.profileSeriesName = 'pombe_division_profile';
tip{end+1} = 'OUTPUT binding: dataseries name for 100-bin normalized intensity profiles';

paramout.scoreSeriesName = 'pombe_division_score';
tip{end+1} = 'OUTPUT binding: dataseries name for frame-wise septum score';

% Static target-selection and Viterbi parameters.
paramout.targetSelectionMode = {'legacy_viterbi','locked_depth','trap_back','legacy_viterbi'};
tip{end+1} = 'Target policy: legacy_viterbi preserves saved runs; locked_depth locks one identity; trap_back selects the resident at the calibrated back every frame and reports identity breaks separately';
paramout.trapDepthDirection = {'right','left','up','down','right'};
tip{end+1} = 'Legacy locked_depth direction only; trap_back uses the existing anchorMode selector as its single orientation setting';
paramout.targetCavityBounds = [];
tip{end+1} = 'trap_back only: required normalized [x y width height] of the cavity, calibrated from the raw movie; excludes neighbouring cells outside the trap';
paramout.targetBackFraction = .30;
tip{end+1} = 'trap_back only: back fraction of the calibrated cavity that the cell pole must reach; its centre may lie farther toward the opening';
paramout.targetMinCavityFraction = .5;
tip{end+1} = 'trap_back only: minimum fraction of the cell mask inside the calibrated cavity';
paramout.targetMinDepth = .60;
tip{end+1} = 'Minimum normalized ROI depth of the target centroid (0 mouth side, 1 back side); calibrate from the trap geometry, not from available cell masks';
paramout.targetDepthMargin = .03;
tip{end+1} = 'Initialization is ambiguous when the two deepest eligible centroids differ by less than this normalized depth';
paramout.targetMinOverlap = .5;
tip{end+1} = 'Minimum intersection divided by the larger mask area for locked identity matching';
paramout.targetMatchMargin = .1;
tip{end+1} = 'Minimum overlap-strength advantage over a second eligible identity match';
paramout.targetRecoveryMaxGap = 2;
tip{end+1} = 'Maximum missing frames before target loss becomes terminal; never reinitialize a different target';
paramout.inputMode = {'auto','label','binary','auto'};
tip{end+1} = 'STATIC: mask input interpretation: auto, label, or binary';

paramout.anchorMode = {'right','left','up','down','center','custom','right'};
tip{end+1} = 'Cell selector: trap_back uses left/right/up/down as the direction toward the closed back, for every frame; legacy modes use an initial anchor';

paramout.anchorX = 0.70;
tip{end+1} = 'STATIC: custom initial target X position in normalized ROI coordinates; used only when anchorMode is custom';

paramout.anchorY = 0.55;
tip{end+1} = 'STATIC: custom initial target Y position in normalized ROI coordinates; used only when anchorMode is custom';

paramout.anchorFrames = 4;
tip{end+1} = 'STATIC: first frames where anchor position contributes to Viterbi cost';

paramout.anchorWeight = 2.0;
tip{end+1} = 'STATIC: initial position matching weight';

paramout.distanceWeight = 1.0;
tip{end+1} = 'STATIC: centroid displacement transition weight';

paramout.areaWeight = 0.8;
tip{end+1} = 'STATIC: area continuity transition weight';

paramout.iouWeight = 0.6;
tip{end+1} = 'STATIC: overlap continuity transition weight';

paramout.maxJumpCellDiameters = 2.5;
tip{end+1} = 'STATIC: maximum centroid jump in approximate cell diameters';

paramout.minArea = 20;
tip{end+1} = 'STATIC: minimum object area in pixels';

paramout.maxArea = inf;
tip{end+1} = 'STATIC: maximum object area in pixels';

paramout.minTrackFrames = 3;
tip{end+1} = 'STATIC: minimum frames before split-stop detection';

paramout.splitAreaDropRatio = 0.65;
tip{end+1} = 'STATIC: area drop ratio versus previous frame for split candidate';

paramout.hardAreaDropRatio = 0.45;
tip{end+1} = 'STATIC: fallback stop ratio versus early typical area';

paramout.splitRadiusCellDiameters = 2.2;
tip{end+1} = 'STATIC: daughter search radius near previous centroid';

paramout.splitCombinedAreaMinRatio = 0.65;
tip{end+1} = 'STATIC: minimum daughter combined area ratio';

paramout.splitCombinedAreaMaxRatio = 1.35;
tip{end+1} = 'STATIC: maximum daughter combined area ratio';

paramout.stopAtSplit = true;
tip{end+1} = 'STATIC: zero output mask after detected split frame';

paramout.segmentationMaxGapFrames = 0;
tip{end+1} = 'STATIC: reject recoverable segmentation failures up to this many frames; 0 preserves legacy behavior, 2 is recommended for tolerant tracking';

paramout.segmentationGapAreaRatio = 0.65;
tip{end+1} = 'STATIC: abrupt area ratio below which to look for a short segmentation failure';

paramout.segmentationRecoveryAreaRatio = 0.8;
tip{end+1} = 'STATIC: minimum recovered area ratio; recovery also requires spatial overlap with the pre-gap cell';

paramout.splitConfirmationFrames = 1;
tip{end+1} = 'STATIC: consecutive observations required to confirm a split/area-loss stop; 1 preserves legacy behavior, 2 is recommended for tolerant tracking';

% Static profile/septum parameters.
paramout.septumMethod = {'profile','transverse2d','transverse2d'};
tip{end+1} = 'STATIC: transverse2d searches for a coherent stripe in the image; profile uses the legacy longitudinal intensity minimum';

paramout.septumLineEdgeFraction = 0.20;
tip{end+1} = 'STATIC: transverse2d excludes this fraction at both longitudinal cell ends';

paramout.septumLineMinCoverage = 0.65;
tip{end+1} = 'STATIC: transverse2d requires both flanks and consistent contrast across this fraction of the cell width';

paramout.septumLineMaxAngle = 30;
tip{end+1} = 'STATIC: maximum stripe tilt in degrees relative to the transverse cell axis';

paramout.septumLineFlankOffsets = [3 5 7];
tip{end+1} = 'STATIC: flank distances in pixels searched by transverse2d';

paramout.septumMinAspectRatio = 1.3;
tip{end+1} = 'STATIC: transverse2d ignores round objects below this longitudinal-to-transverse extent ratio';

paramout.profileBins = 100;
tip{end+1} = 'STATIC: number of normalized longitudinal profile bins';

paramout.profileSmoothBins = 3;
tip{end+1} = 'STATIC: moving average smoothing window for the legacy profile score';

paramout.profileEdgeIgnoreFraction = 0.12;
tip{end+1} = 'STATIC: fraction of both profile edges ignored for septum scoring';

paramout.septumPolarity = {'dark','bright','absolute','dark'};
tip{end+1} = 'STATIC: septum contrast polarity in normalized profile';

paramout.septumScoreThreshold = 1.5;
tip{end+1} = 'STATIC: detection threshold; profile uses profile IQR units, transverse2d uses local contrast/noise units';

paramout.debug = false;
tip{end+1} = 'STATIC: verbose diagnostic output';

paramout.tip = tip;
end

function out = normalizeChannelList(ch)
if isempty(ch)
    out = {};
    return;
end
if ischar(ch)
    ch = cellstr(ch);
elseif isstring(ch) || isnumeric(ch) || islogical(ch) || iscategorical(ch)
    ch = cellstr(string(ch(:)));
elseif ~iscell(ch)
    ch = {char(string(ch))};
end

out = {};
for i = 1:numel(ch)
    item = ch{i};
    if isempty(item)
        continue;
    end
    if ischar(item)
        out{end+1} = item; %#ok<AGROW>
    elseif isstring(item) || isnumeric(item) || islogical(item) || iscategorical(item)
        vals = cellstr(string(item(:)));
        out = [out vals(:)']; %#ok<AGROW>
    end
end

out = cellfun(@(x) char(strtrim(string(x))), out(:)', 'UniformOutput', false);
out = out(~cellfun(@isempty, out));
out = unique(out, 'stable');
end

function preferred = choosePreferredInstanceChannel(listChannels)
preferred = 'none';
if isempty(listChannels), return; end
score = zeros(1, numel(listChannels));
for i = 1:numel(listChannels)
    nm = lower(char(string(listChannels{i})));
    if startsWith(nm, 'results_'), score(i) = score(i) + 10; end
    if contains(nm, 'cell'), score(i) = score(i) + 5; end
    if contains(nm, 'track') || contains(nm, 'prob') || contains(nm, 'dic')
        score(i) = score(i) - 5;
    end
end
[bestScore, idx] = max(score);
if bestScore > 0
    preferred = listChannels{idx};
elseif ~isempty(listChannels{1})
    preferred = listChannels{1};
end
end

function preferred = choosePreferredRawChannel(listChannels)
preferred = 'none';
if isempty(listChannels), return; end
score = zeros(1, numel(listChannels));
for i = 1:numel(listChannels)
    nm = lower(char(string(listChannels{i})));
    if contains(nm, 'dic') || contains(nm, 'phase')
        score(i) = score(i) + 10;
    end
    if contains(nm, 'focus')
        score(i) = score(i) + 5;
    end
    if startsWith(nm, 'results_') || contains(nm, 'prob') || contains(nm, 'mask')
        score(i) = score(i) - 10;
    end
end
[bestScore, idx] = max(score);
if bestScore > 0
    preferred = listChannels{idx};
elseif ~isempty(listChannels{1})
    preferred = listChannels{1};
end
end
