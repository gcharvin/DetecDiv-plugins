function spec = executionSpec()
% Fixed contract for the unchanged, per-ROI legacy analysis function.
spec = struct();
spec.summary = ['Runs the original Xtra full-channel classification, RLS, segmentation, ' ...
    'and fluorescence function on each selected ROI.'];
spec.staticKeys = {};
spec.outputKeys = {};
spec.defaultImportKeys = {};
spec.defaults = struct();
spec.labels = struct();
spec.tips = struct();
spec.choices = struct();
spec.contract = struct();
% ROI/FOV/frame selection arrives through run context or the preceding node.
% The module does not require separate configured data inputs.
spec.contract.in = localPort('roiList', 'roiList', false, 'edge');
spec.contract.out = [localPort('roiList', 'roiList', true, 'edge'), ...
    localPort('masks', 'maskSet', true, 'edge')];
spec.contract.selectors = struct('channelParam', '', 'channelsParam', '', ...
    'framesParam', '', 'outputNameParam', '');
spec.contract.parameters = struct('run', {{}}, 'static', {{}}, 'data', {{}});
spec.contract.requirements = struct();
spec.contract.requirements.roi = struct('required', true, 'channelsMin', 6, 'dataSeries', false);
spec.contract.binding = struct('scope', 'roi', 'outputScope', 'roi', ...
    'mode', 'none', 'selectorKeys', {{}}, 'resolveAt', 'run');
spec.contract.capabilities = struct('preservesRoiList', true, ...
    'roiChannels', true, 'outputsChannels', false, 'roiDataSeries', false, ...
    'outputsDataSeries', false, 'roiMasks', true, 'outputsMasks', true);
spec.contract.resources = struct();
spec.contract.resources.in = struct([]);
spec.contract.resources.out = localResource('mask', 'segmentation', ...
    'seg', '', 'masks', '', false, 'roiMask');
spec.contract.summary = spec.summary;
end

function p = localPort(name, type, required, source)
p = struct('name', name, 'type', type, 'required', logical(required), 'source', source);
end

function r = localResource(type, role, symbol, param, port, nameParam, required, transfer)
r = struct('type', type, 'role', role, 'symbol', symbol, 'param', param, ...
    'port', port, 'nameParam', nameParam, 'required', logical(required), ...
    'transfer', transfer);
end
