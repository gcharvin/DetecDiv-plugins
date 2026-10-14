function roiIndices = requireWholeFovRoiSelection(shallowObj, fovIndices, ctx)
% Resolve run-selected ROI objects to their local indices in each selected FOV.
roiIndices = [];
selected = [];
if isfield(ctx, 'sel') && isstruct(ctx.sel) && ...
        isfield(ctx.sel, 'rois') && ~isempty(ctx.sel.rois)
    roiIndices = unique(double(ctx.sel.rois(:)'), 'stable');
    for fovIdx = fovIndices
        count = numel(shallowObj.fov(fovIdx).roi);
        if any(~isfinite(roiIndices) | roiIndices < 1 | roiIndices > count | roiIndices ~= fix(roiIndices))
            error('saveCroppedImagesXConservative:InvalidRoiSelection', ...
                'The ROI selection is invalid for FOV %d, which has %d ROIs.', fovIdx, count);
        end
    end
    return;
end
if isfield(ctx, 'roiList') && ~isempty(ctx.roiList)
    selected = ctx.roiList;
end
if isempty(selected)
    return; % An empty selection means all ROIs, preserving the legacy default.
end
expectedKeys = strings(0,1);
for fovIdx = fovIndices
    fovObj = shallowObj.fov(fovIdx);
    for r = 1:numel(fovObj.roi)
        expectedKeys(end+1,1) = string(fovObj.id) + "|" + string(fovObj.roi(r).id); %#ok<AGROW>
    end
end
actualKeys = strings(0,1);
for r = 1:numel(selected)
    roiObj = selected(r);
    fovId = '';
    try
        if isa(roiObj.parent, 'fov')
            fovId = char(string(roiObj.parent.id));
        end
    catch
    end
    if isempty(fovId)
        candidates = strings(0,1);
        for fovIdx = fovIndices
            fovObj = shallowObj.fov(fovIdx);
            if any(strcmp({fovObj.roi.id}, char(string(roiObj.id))))
                candidates(end+1,1) = string(fovObj.id); %#ok<AGROW>
            end
        end
        if numel(candidates) ~= 1
            error('saveCroppedImagesXConservative:AmbiguousRoiSelection', ...
                'Cannot identify the parent FOV of ROI "%s" uniquely.', char(string(roiObj.id)));
        end
        fovId = char(candidates(1));
    end
    actualKeys(end+1,1) = string(fovId) + "|" + string(roiObj.id); %#ok<AGROW>
end
if any(~ismember(actualKeys, expectedKeys))
    error('saveCroppedImagesXConservative:RoiOutsideSelectedFovs', ...
        'The run ROI list contains an ROI outside the selected FOVs.');
end
if isequal(sort(expectedKeys), sort(actualKeys))
    return; % No ROI filter is needed when the whole selected FOV is requested.
end

for fovIdx = fovIndices
    fovObj = shallowObj.fov(fovIdx);
    keep = false(1, numel(fovObj.roi));
    for r = 1:numel(fovObj.roi)
        key = string(fovObj.id) + "|" + string(fovObj.roi(r).id);
        keep(r) = any(actualKeys == key);
    end
    localIndices = find(keep);
    if isempty(roiIndices)
        roiIndices = localIndices;
    elseif ~isequal(roiIndices, localIndices)
        error('saveCroppedImagesXConservative:InconsistentRoiSelection', ...
            ['The legacy wrapper accepts the same local ROI indices for each selected FOV. ' ...
             'Choose matching ROI indices across FOVs or run those FOVs separately.']);
    end
end
if isempty(roiIndices)
    error('saveCroppedImagesXConservative:EmptyRoiSelection', ...
        'No selected ROIs belong to the selected FOVs.');
end
end
