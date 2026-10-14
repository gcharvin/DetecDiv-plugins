function [temporalClassi, temporalNet, pixelClassi, pixelNet] = loadLegacyInputs()
% Resolve the original script's four explicit classifier/network arguments.
persistent cachedKey cachedValues
allPaths = xtraFullChannelsConservative.modelPaths();
if ispc
    paths = allPaths.windows;
    host = 'Windows';
elseif ismac
    paths = allPaths.macOS;
    host = 'macOS';
elseif isunix
    paths = allPaths.linux;
    host = 'Linux';
else
    error('xtraFullChannelsConservative:UnsupportedHost', 'Unsupported MATLAB host.');
end
names = fieldnames(paths);
missing = {};
for i = 1:numel(names)
    value = char(string(paths.(names{i})));
    if isempty(value) || exist(value, 'file') ~= 2
        missing{end+1} = names{i}; %#ok<AGROW>
    end
end
if ~isempty(missing)
    error('xtraFullChannelsConservative:ModelPathsNotConfigured', ...
        'Configure existing absolute model paths for %s in modelPaths.m; unavailable fields: %s.', ...
        host, strjoin(missing, ', '));
end

cacheKey = strjoin({paths.temporalClassiFile, paths.temporalNetworkFile, ...
    paths.pixelClassiFile, paths.pixelNetworkFile}, '|');
if ~isempty(cachedKey) && strcmp(cachedKey, cacheKey)
    temporalClassi = cachedValues{1};
    temporalNet = cachedValues{2};
    pixelClassi = cachedValues{3};
    pixelNet = cachedValues{4};
    return;
end

[temporalClassi, msg1] = classiLoad(paths.temporalClassiFile);
[pixelClassi, msg2] = classiLoad(paths.pixelClassiFile);
if ~isa(temporalClassi, 'classi') || ~isa(pixelClassi, 'classi')
    error('xtraFullChannelsConservative:InvalidClassifierSnapshot', ...
        'Could not load the original classi snapshots: %s %s', char(string(msg1)), char(string(msg2)));
end
temporalNet = localLoadNetwork(paths.temporalNetworkFile, 'temporal');
pixelNet = localLoadNetwork(paths.pixelNetworkFile, 'pixel');
cachedKey = cacheKey;
cachedValues = {temporalClassi, temporalNet, pixelClassi, pixelNet};
end

function net = localLoadNetwork(file, role)
loaded = load(file);
preferred = {'classifier', 'net', 'netLSTM_dag', 'netCNN', 'netLSTM'};
net = [];
for i = 1:numel(preferred)
    if isfield(loaded, preferred{i}) && localIsNetwork(loaded.(preferred{i}))
        net = loaded.(preferred{i});
        break;
    end
end
if isempty(net)
    fields = fieldnames(loaded);
    for i = 1:numel(fields)
        if localIsNetwork(loaded.(fields{i}))
            net = loaded.(fields{i});
            break;
        end
    end
end
if isempty(net)
    error('xtraFullChannelsConservative:InvalidNetworkFile', ...
        'No supported MATLAB network was found in the %s file %s.', role, file);
end
end

function tf = localIsNetwork(value)
tf = isa(value, 'DAGNetwork') || isa(value, 'SeriesNetwork') || isa(value, 'dlnetwork');
end
