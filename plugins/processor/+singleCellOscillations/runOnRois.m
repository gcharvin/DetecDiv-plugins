function [perRoi, normalizedCycles, metadata] = runOnRois(roiList, varargin)
% singleCellOscillations.runOnRois  Convenience entry point outside pipeline.
%
% Example:
%   detecdiv_plugins_addpath
%   [perRoi, cycles, meta] = singleCellOscillations.runOnRois(shallowObj.fov(1).roi, ...
%       'classification_data', 'div_1', ...
%       'labelVariable', 'div_1 / labels', ...
%       'fluorescence_data', 'channel_quantification', ...
%       'fluorescenceVariable', 'channel_quantification / Ratio_Mean_NoBckg_channel001_z001_channel002_z001_cyto');

p = inputParser;
defaults = singleCellOscillations.setparam(struct());
names = fieldnames(rmfield(defaults, 'tip'));
for i = 1:numel(names)
    addParameter(p, names{i}, defaults.(names{i}));
end
parse(p, varargin{:});

param = rmfield(defaults, 'tip');
for i = 1:numel(names)
    param.(names{i}) = p.Results.(names{i});
end

perRoi = table(string.empty(0,1), string.empty(0,1), zeros(0,1), ...
    'VariableNames', {'ROIId','Status','AcceptedCycles'});
normalizedCycles = table();
metadata = table();

for i = 1:numel(roiList)
    [~, dataout] = singleCellOscillations.process(param, roiList(i), struct());
    roiList(i).data = dataout;
    roiId = localRoiId(roiList(i));

    normIdx = find(arrayfun(@(x) strcmp(char(string(x.groupid)), param.normalizedCyclesOutputName), dataout), 1);
    metaIdx = find(arrayfun(@(x) strcmp(char(string(x.groupid)), param.cycleMetadataOutputName), dataout), 1);

    status = "";
    nAccepted = 0;
    if ~isempty(metaIdx)
        Tm = dataout(metaIdx).data;
        if isfield(dataout(metaIdx).userData, 'status')
            status = string(dataout(metaIdx).userData.status);
        end
        if istable(Tm) && height(Tm) > 0
            Tm.ROIId = repmat(string(roiId), height(Tm), 1);
            metadata = appendTable(metadata, movevars(Tm, 'ROIId', 'Before', 1));
            nAccepted = sum(Tm.accepted);
        end
    end
    if ~isempty(normIdx)
        Tn = dataout(normIdx).data;
        if istable(Tn) && height(Tn) > 0
            Tn.ROIId = repmat(string(roiId), height(Tn), 1);
            normalizedCycles = appendTable(normalizedCycles, movevars(Tn, 'ROIId', 'Before', 1));
        end
    end

    perRoi = [perRoi; table(string(roiId), status, nAccepted, ...
        'VariableNames', {'ROIId','Status','AcceptedCycles'})]; %#ok<AGROW>
end
end

function out = appendTable(out, T)
if isempty(out) || width(out) == 0
    out = T;
else
    out = [out; T];
end
end

function id = localRoiId(roiobj)
id = 'roi';
try
    if isprop(roiobj, 'id') && ~isempty(roiobj.id)
        id = char(string(roiobj.id));
    end
catch
end
end
