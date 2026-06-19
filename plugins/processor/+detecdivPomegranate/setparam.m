function paramout = setparam(ctx)
% detecdivPomegranate.setparam  Defaults for Pomegranate-like 3D cytometry.

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

paramout = struct();
tip = {};

paramout.zStackChannelNames = choosePreferredZStackChannels(listChannels);
tip{end+1} = 'INPUT binding: DIC/BF z-stack channels, ordered from bottom to top z';

paramout.cellMaskChannelName = choosePreferredMaskChannel(listChannels);
tip{end+1} = 'INPUT binding: selected cell mask channel, typically cell_of_interest';

paramout.scoreSeriesName = 'pombe_division_score';
tip{end+1} = 'INPUT binding: septum score dataseries used to select the measurement frame';

paramout.focusSeriesName = 'DIC_focus_best_z';
tip{end+1} = 'INPUT binding: best-focus z dataseries produced by bestFocusPlane';

paramout.cellInformationSeriesName = 'cell_information';
tip{end+1} = 'OUTPUT binding: non-temporal dataseries storing measurements and QC in userData';

paramout.outputDir = defaultOutputRoot(ctx);
tip{end+1} = 'OUTPUT artifact folder for Pomegranate-compatible CSV/Excel files';

paramout.resultsWorkbookName = 'detecdiv_pomegranate_results.xlsx';
tip{end+1} = 'OUTPUT artifact: Excel workbook collecting Pomegranate-compatible results';

paramout.writeCsv = true;
tip{end+1} = 'STATIC: write one Pomegranate-compatible *_Results_Full.csv file per ROI';

paramout.writeExcel = true;
tip{end+1} = 'STATIC: write/update an Excel workbook with Pomegranate-compatible columns';

paramout.writeQcImages = true;
tip{end+1} = 'STATIC: write PNG QC images in each ROI folder';

paramout.writeMosaicImage = true;
tip{end+1} = 'STATIC: write/update a PNG mosaic next to the Excel workbook';

paramout.mosaicFileName = 'detecdiv_pomegranate_mosaic.png';
tip{end+1} = 'OUTPUT artifact: PNG mosaic collecting all processed ROI QC tiles';

paramout.experimentName = '';
tip{end+1} = 'STATIC: experiment name written in the Pomegranate-compatible output table';

paramout.frameSelectionMode = {'first_septum_detected','max_score','manual_frame','first_valid_mask','first_septum_detected'};
tip{end+1} = 'STATIC: frame used for reconstruction and measurement';

paramout.manualFrame = 1;
tip{end+1} = 'STATIC: frame used when frameSelectionMode is manual_frame';

paramout.voxelSizeXY = 0.103;
tip{end+1} = 'STATIC: XY pixel size in microns';

paramout.voxelSizeZ = 0.1;
tip{end+1} = 'STATIC: Z spacing in microns';

paramout.pomegranate_gapClosureSizePx = 10;
tip{end+1} = 'STATIC: Pomegranate gap closure size in pixels';

paramout.pomegranate_bandCoverageRadiusPx = 0;
tip{end+1} = 'STATIC: Pomegranate band coverage / enlarge radius in pixels';

paramout.pomegranate_interpolationSmoothingPx = 5;
tip{end+1} = 'STATIC: Pomegranate interpolation smoothing interval in pixels';

paramout.pomegranate_solidityThreshold = 0.9;
tip{end+1} = 'STATIC: minimum mid-plane solidity, matching ImageJ Pomegranate ROI filtering';

paramout.pomegranate_roiMarginPx = 10;
tip{end+1} = 'STATIC: margin parameter kept for ImageJ Pomegranate compatibility and reported in outputs';

paramout.pomegranate_segmentRadiusPaddingPx = 1;
tip{end+1} = 'STATIC: added radius in pixels, matching the +1 used by ImageJ Pomegranate';

paramout.pomegranate_minSegmentRadiusPx = 1.5;
tip{end+1} = 'STATIC: ignore reconstructed disks below this pixel radius';

paramout.pomegranate_skeletonPruneIterations = 0;
tip{end+1} = 'STATIC: optional skeleton spur pruning iterations';

paramout.storeReconstructionMask = true;
tip{end+1} = 'STATIC: store the 3D reconstructed mask in userData';

paramout.debug = false;
tip{end+1} = 'STATIC: verbose diagnostic output';

paramout.tip = tip;
end

function out = defaultOutputRoot(ctx)
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
    if isempty(item), continue; end
    if ischar(item)
        out{end+1} = item; %#ok<AGROW>
    elseif isstring(item) || isnumeric(item) || islogical(item) || iscategorical(item)
        out = [out cellstr(string(item(:)))']; %#ok<AGROW>
    end
end
out = cellfun(@(x) char(strtrim(string(x))), out(:)', 'UniformOutput', false);
out = unique(out(~cellfun(@isempty, out)), 'stable');
end

function preferred = choosePreferredMaskChannel(listChannels)
preferred = 'cell_of_interest';
if isempty(listChannels), return; end
matches = strcmpi(listChannels, 'cell_of_interest');
if any(matches)
    preferred = listChannels{find(matches, 1, 'first')};
end
end

function preferred = choosePreferredZStackChannels(listChannels)
preferred = {};
if isempty(listChannels), return; end
keep = false(1, numel(listChannels));
for i = 1:numel(listChannels)
    nm = lower(char(string(listChannels{i})));
    isZ = (~isempty(regexp(nm, 'z[^a-z0-9]*\d+|\d+[^a-z0-9]*z', 'once')) || ...
        ~isempty(regexp(nm, '(^|_)dic[_-]?z?\d+$|(^|_)z\d+$|dic_z\d+', 'once')) || ...
        contains(nm, 'dic_z') || contains(nm, 'dic-z'));
    isBad = startsWith(nm, 'results_') || contains(nm, 'prob') || ...
        contains(nm, 'mask') || contains(nm, 'focus') || contains(nm, 'cell_of_interest');
    keep(i) = isZ && ~isBad;
end
preferred = sortZChannels(listChannels(keep));
if isempty(preferred)
    preferred = {'<all>'};
end
end

function out = sortZChannels(channels)
out = channels;
if numel(out) < 2, return; end
z = nan(1, numel(out));
for i = 1:numel(out)
    tok = regexp(char(string(out{i})), '(\d+)$', 'tokens', 'once');
    if ~isempty(tok)
        z(i) = str2double(tok{1});
    end
end
if all(isfinite(z))
    [~, ord] = sort(z);
    out = out(ord);
end
end
