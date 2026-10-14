function indices = selectedFovIndices(shallowObj, ctx, roiobj)
% Resolve the pipeline's selected FOVs to indices in the complete project.
indices = [];
if isfield(ctx, 'sel') && isstruct(ctx.sel) && isfield(ctx.sel, 'fovs') && ~isempty(ctx.sel.fovs)
    indices = unique(double(ctx.sel.fovs(:)'), 'stable');
elseif isfield(ctx, 'fovList') && ~isempty(ctx.fovList)
    for i = 1:numel(ctx.fovList)
        candidateId = char(string(ctx.fovList(i).id));
        hit = find(arrayfun(@(f) strcmp(char(string(f.id)), candidateId), shallowObj.fov));
        if numel(hit) ~= 1
            error('saveCroppedImagesXConservative:FovMapping', ...
                'Could not map selected FOV "%s" uniquely to the project.', candidateId);
        end
        indices(end+1) = hit; %#ok<AGROW>
    end
elseif isprop(roiobj, 'parent') && isa(roiobj.parent, 'fov')
    candidateId = char(string(roiobj.parent.id));
    indices = find(arrayfun(@(f) strcmp(char(string(f.id)), candidateId), shallowObj.fov));
else
    indices = 1:numel(shallowObj.fov);
end
indices = unique(indices, 'stable');
if isempty(indices) || any(indices < 1 | indices > numel(shallowObj.fov) | indices ~= fix(indices))
    error('saveCroppedImagesXConservative:InvalidFovSelection', ...
        'The selected FOV list is empty or contains invalid project indices.');
end
end
