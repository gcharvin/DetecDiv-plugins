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

% Explicit output bindings.
paramout.outputMaskChannelName = 'cell_of_interest';
tip{end+1} = 'OUTPUT binding: binary mask channel for the tracked cell of interest';

paramout.profileSeriesName = 'pombe_division_profile';
tip{end+1} = 'OUTPUT binding: dataseries name for 100-bin normalized intensity profiles';

paramout.scoreSeriesName = 'pombe_division_score';
tip{end+1} = 'OUTPUT binding: dataseries name for frame-wise septum score';

% Static Viterbi parameters.
paramout.inputMode = {'auto','label','binary','auto'};
tip{end+1} = 'STATIC: mask input interpretation: auto, label, or binary';

paramout.anchorMode = {'right','left','center','custom','right'};
tip{end+1} = 'STATIC: initial cell selector in normalized ROI coordinates';

paramout.anchorX = 0.70;
tip{end+1} = 'STATIC: custom initial target X position in normalized ROI coordinates';

paramout.anchorY = 0.55;
tip{end+1} = 'STATIC: custom initial target Y position in normalized ROI coordinates';

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

% Static profile/septum parameters.
paramout.profileBins = 100;
tip{end+1} = 'STATIC: number of normalized longitudinal profile bins';

paramout.profileSmoothBins = 3;
tip{end+1} = 'STATIC: moving average smoothing window for profile and score';

paramout.profileEdgeIgnoreFraction = 0.12;
tip{end+1} = 'STATIC: fraction of both profile edges ignored for septum scoring';

paramout.septumPolarity = {'dark','bright','absolute','dark'};
tip{end+1} = 'STATIC: septum contrast polarity in normalized profile';

paramout.septumScoreThreshold = 1.5;
tip{end+1} = 'STATIC: septum is detected when septumScore is above this robust-normalized threshold';

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
