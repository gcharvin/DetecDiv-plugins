function runLegacyOnce(shallowObj, ctx, param, fovIndices, roiIndices)
% The pipeline invokes processors per ROI; invoke the project-level routine once.
persistent lastKey completed
runId = '';
if isfield(param, 'runId') && ~isempty(param.runId)
    runId = char(string(param.runId));
elseif isfield(ctx, 'run') && isstruct(ctx.run) && isfield(ctx.run, 'runId')
    runId = char(string(ctx.run.runId));
end
if isempty(runId)
    error('saveCroppedImagesXConservative:MissingRunId', ...
        'pipeline2 did not provide a runId; cannot safely guard the project-wide legacy call.');
end
nodeId = 'saveCroppedImagesXConservative';
if isfield(ctx, 'pipeline') && isstruct(ctx.pipeline) && isfield(ctx.pipeline, 'currentNode')
    nodeId = char(string(ctx.pipeline.currentNode));
end
key = [runId '|' nodeId];
if isempty(lastKey) || ~strcmp(lastKey, key)
    lastKey = key;
    completed = false;
end
if completed
    return;
end

frames = saveCroppedImagesXConservative.selectedFrames(ctx);
allFrames = isempty(frames) || (isnumeric(frames) && all(frames == -1));
if ~allFrames
    frames = double(frames(:)');
    if ~isequal(frames, 1:numel(frames))
        error('saveCroppedImagesXConservative:LegacyFrameSelectionLimit', ...
            ['The unchanged function sizes ROI output by the number of selected frames, ' ...
             'then indexes it by absolute frame number. It can safely accept only a prefix starting at frame 1.']);
    end
end
if allFrames
    saveCroppedImagesXConservative.prepareAllFrames(shallowObj, fovIndices);
end
% >>> ADAPTATION PARALLEL POOL 2026-10-15: respect job CPU/RAM admission.
% Keep the historical parfor and scientific calculations unchanged. The
% guard closes only the pool created here, on success and on exceptions.
poolPlan = saveCroppedImagesXConservative.planReadPool(shallowObj,ctx,param,fovIndices);
poolGuard = saveCroppedImagesXConservative.openReadPool(poolPlan); %#ok<NASGU>
% <<< FIN DE L'ADAPTATION PARALLEL POOL
% >>> ADAPTATION PIPELINE 2026-10-14: transmettre le parametre historique cut
blockArgs = saveCroppedImagesXConservative.blockSizeArguments(param);
% <<< FIN DE L'ADAPTATION (le script historique reste inchange)
if allFrames
    saveCroppedImagesXConservative.saveCroppedImages_X(shallowObj, ...
        'fov', fovIndices, 'rois', roiIndices, blockArgs{:});
else
    saveCroppedImagesXConservative.saveCroppedImages_X(shallowObj, ...
        'frames', frames, 'fov', fovIndices, 'rois', roiIndices, blockArgs{:});
end
completed = true;
end
