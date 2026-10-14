function [paramout, dataout, imageout] = process(param, roiobj, ctx)
% Pipeline adapter around the unchanged project-level legacy function.
if nargin < 3 || isempty(ctx)
    ctx = struct();
elseif ~isstruct(ctx)
    ctx = struct('frames', ctx);
end
if nargin == 0 || isempty(param)
    paramout = saveCroppedImagesXConservative.setparam();
    dataout = [];
    imageout = [];
    return;
end
if isfield(param, 'parallel') && logical(param.parallel)
    error('saveCroppedImagesXConservative:ParallelNotSupported', ...
        'Disable processor parallel execution: the unchanged legacy function processes the selected project FOVs in one pass.');
end

shallowObj = [];
if isfield(ctx, 'shallow') && ~isempty(ctx.shallow)
    shallowObj = ctx.shallow;
elseif isfield(ctx, 'shallowObj') && ~isempty(ctx.shallowObj)
    shallowObj = ctx.shallowObj;
end
if ~isa(shallowObj, 'shallow')
    error('saveCroppedImagesXConservative:MissingProject', ...
        'The pipeline context must provide the shallow project object.');
end

fovIndices = saveCroppedImagesXConservative.selectedFovIndices(shallowObj, ctx, roiobj);
roiIndices = saveCroppedImagesXConservative.requireWholeFovRoiSelection(shallowObj, fovIndices, ctx);
saveCroppedImagesXConservative.runLegacyOnce(shallowObj, ctx, param, fovIndices, roiIndices);

legacyRoi = saveCroppedImagesXConservative.loadLegacyOutput(shallowObj, roiobj);
roiobj.image = legacyRoi.image;
roiobj.data = legacyRoi.data;
roiobj.display = legacyRoi.display;
roiobj.channelid = legacyRoi.channelid;
roiobj.results = legacyRoi.results;
roiobj.train = legacyRoi.train;

paramout = struct();
paramout.saveChannels = legacyRoi.display.channel;
dataout = roiobj.data;
imageout = roiobj.image;
end
