function spec = executionSpec()
% Fixed adapter contract; parameters come from pipeline run selection.
spec = struct();
spec.summary = ['Runs the unchanged saveCroppedImages_X function once for the selected FOVs; ' ...
    'the wrapper returns its saved ROI images to pipeline2.'];
spec.staticKeys = {};
spec.outputKeys = {};
spec.defaultImportKeys = {};
spec.defaults = struct();
spec.labels = struct();
spec.tips = struct();
spec.choices = struct();
spec.contract = struct();
% Project/FOV/ROI/frame selection arrives through run context. The node has
% no required data input; it may receive an roiList edge when chained.
spec.contract.in = localPort('roiList', 'roiList', false, 'edge');
spec.contract.out = [localPort('roiList', 'roiList', true, 'edge'), ...
    localPort('channels', 'channelSet', true, 'edge')];
spec.contract.selectors = struct('channelParam', '', 'channelsParam', '', ...
    'framesParam', 'frames', 'outputNameParam', '');
spec.contract.parameters = struct('run', {{}}, 'static', {{}}, 'data', {{}});
spec.contract.requirements = struct();
% The run engine selects ROI objects from the project/FOV context at execution.
spec.contract.requirements.roi = struct('required', false, 'channelsMin', 0, 'dataSeries', false);
% ADAPTATION VALIDATION 2026-10-15: extraction materializes the raw channels,
% even when newly identified ROIs still advertise only "Channel 1".
spec.contract.binding = struct('scope', 'images', 'outputScope', 'roi', ...
    'mode', 'none', 'selectorKeys', {{}}, 'resolveAt', 'run', ...
    'transfer', 'imagesToRoi');
spec.contract.capabilities = struct('preservesRoiList', true, ...
    'roiChannels', true, 'outputsChannels', true, 'roiDataSeries', false, ...
    'outputsDataSeries', false, 'roiMasks', false, 'outputsMasks', false);
spec.contract.resources = struct();
spec.contract.resources.in = struct([]);
spec.contract.resources.out = struct([]);
spec.contract.summary = spec.summary;
end

function p = localPort(name, type, required, source)
p = struct('name', name, 'type', type, 'required', logical(required), 'source', source);
end
