function [score, position, info] = scoreTransverseSeptum(raw, mask, param)
%SCORETRANSVERSESEPTUM Look for a coherent transverse stripe inside a cell.
% The cell axis only constrains the search geometry. Intensity is compared
% point by point across a 2-D line and its two flanks, without averaging the
% cell into a longitudinal profile. Coordinates in info are ROI pixels.

if nargin < 3, param = struct(); end
validateattributes(raw, {'numeric'}, {'real','2d','finite'});
validateattributes(mask, {'numeric','logical'}, {'real','2d','finite'});
if ~isequal(size(raw), size(mask))
    error('detectViterbiPombeDivisionFrame:SeptumImageSize', ...
        'Raw image and cell mask must have identical sizes.');
end
mask = mask > 0;
score = NaN; position = NaN;
info = struct('coverage',NaN,'angle',NaN,'flankOffset',NaN, ...
    'noiseScale',NaN,'lineEndpoints',nan(2,2));
[yy, xx] = find(mask);
if numel(xx) < 10, return; end
score = 0;

coords = [double(xx), double(yy)];
center = mean(coords, 1);
relative = coords - center;
[~, ~, V] = svd(relative, 'econ');
u = V(:,1).'; n = [-u(2), u(1)];
s = relative * u.'; t = relative * n.';
cellLength = max(s) - min(s); cellWidth = max(t) - min(t);
if cellWidth < 3 || cellLength / cellWidth < value(param,'septumMinAspectRatio',1.3)
    return;
end

edge = value(param,'septumLineEdgeFraction',0.2);
coverageMin = value(param,'septumLineMinCoverage',0.65);
angleMax = value(param,'septumLineMaxAngle',30);
offsets = value(param,'septumLineFlankOffsets',[3 5 7]);
if edge < 0 || edge >= 0.5 || coverageMin <= 0 || coverageMin > 1 || ...
        angleMax < 0 || angleMax >= 90 || any(~isfinite(offsets)) || ...
        isempty(offsets) || any(offsets <= 0)
    error('detectViterbiPombeDivisionFrame:SeptumLineParameters', ...
        'Invalid line search parameters: check edges, coverage, angles and positive flank offsets.');
end
polarity = choice(param,'septumPolarity','dark');
if ~any(strcmp(polarity,{'dark','bright','absolute'}))
    error('detectViterbiPombeDivisionFrame:SeptumPolarity', ...
        'Septum polarity must be dark, bright or absolute.');
end

raw = double(raw);
raw = imgaussfilt(raw,0.8,'Padding','replicate');
interior = bwdist(~mask);
residual = raw - imgaussfilt(raw,3,'Padding','replicate');
noiseValues = residual(interior >= 2);
if isempty(noiseValues), return; end
noise = 1.4826 * median(abs(noiseValues - median(noiseValues)));
% A relative floor keeps smooth synthetic/quantized images finite without
% introducing an intensity-dependent threshold under changes of gain.
dynamicRange = max(raw(mask)) - min(raw(mask));
noise = max(noise, max(dynamicRange * 1e-6, eps(max(abs(raw(mask))))));
info.noiseScale = noise;

scanS = linspace(min(s) + edge * cellLength, max(s) - edge * cellLength, 51).';
scanT = linspace(-0.75 * cellWidth, 0.75 * cellWidth, max(25,ceil(1.5 * cellWidth)));
angles = unique([linspace(-angleMax,angleMax,7),0]);
for angle = angles
    lineAxis = n * cosd(angle) + u * sind(angle);
    normal = u * cosd(angle) - n * sind(angle);
    x = center(1) + scanS * u(1) + scanT * lineAxis(1);
    y = center(2) + scanS * u(2) + scanT * lineAxis(2);
    inside = interp2(interior,x,y,'linear',0) >= 1.5;
    middle = interp2(raw,x,y,'linear',NaN);
    for offset = offsets(:).'
        xLeft = x - offset * normal(1); yLeft = y - offset * normal(2);
        xRight = x + offset * normal(1); yRight = y + offset * normal(2);
        valid = inside & interp2(interior,xLeft,yLeft,'linear',0) >= 1.5 & ...
            interp2(interior,xRight,yRight,'linear',0) >= 1.5;
        left = interp2(raw,xLeft,yLeft,'linear',NaN);
        right = interp2(raw,xRight,yRight,'linear',NaN);
        dark = min(left-middle,right-middle) / noise;
        bright = min(middle-left,middle-right) / noise;
        switch polarity
            case 'bright', signals = {bright};
            case 'absolute', signals = {dark,bright};
            otherwise, signals = {dark};
        end
        for p = 1:numel(signals)
            signal = signals{p};
            validSignal = valid & isfinite(signal);
            counts = sum(validSignal,2);
            response = signal; response(~validSignal) = NaN;
            % Count against the whole interior section, including points
            % whose flanks are invalid. Otherwise a short vacuole boundary
            % could appear coherent after its unsupported ends are removed.
            coverage = sum(response > 0.75,2) ./ max(sum(inside,2),1);
            % Both flanks must remain inside the cell over most of the
            % transverse section, so membrane/edge contrast is excluded.
            eligible = counts >= 10 & counts >= coverageMin * sum(inside,2) & ...
                coverage >= coverageMin;
            % Lower-quartile contrast rewards a stripe spanning the
            % width; a few very dark pixels in a vacuole cannot dominate.
            candidateScores = max(0,prctile(response,25,2)) .* coverage;
            candidateScores(~eligible) = 0;
            [candidateScore,k] = max(candidateScores);
            if candidateScore > score
                score = candidateScore;
                position = (scanS(k) - min(s)) / cellLength;
                info.coverage = coverage(k);
                info.angle = angle;
                info.flankOffset = offset;
                v = validSignal(k,:);
                extent = [min(scanT(v));max(scanT(v))];
                info.lineEndpoints = center + scanS(k) * u + extent * lineAxis;
            end
        end
    end
end
end

function result = value(param,name,fallback)
result = fallback;
if isfield(param,name) && ~isempty(param.(name))
    result = double(param.(name));
end
if any(~isfinite(result))
    error('detectViterbiPombeDivisionFrame:SeptumLineParameters', ...
        'Parameter %s must be finite.',name);
end
end

function result = choice(param,name,fallback)
result = fallback;
if isfield(param,name) && ~isempty(param.(name))
    raw = param.(name);
    if iscell(raw), raw = raw{end}; end
    result = lower(strtrim(char(string(raw))));
end
end
