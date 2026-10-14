function prepareAllFrames(shallowObj, fovIndices)
% ADAPTATION PIPELINE 2026-10-14: hydrate lazy raw metadata before legacy all.
% The historical script reads srclist{1} before its first readImage call.
for index = fovIndices(:)'
    f = shallowObj.fov(index);
    if isempty(f.srclist) || isempty(f.srclist{1})
        reference = f.readImage(1,1);
        if isempty(reference) || isempty(f.srclist) || isempty(f.srclist{1})
            error('saveCroppedImagesXConservative:RawFrameListUnavailable', ...
                'Cannot resolve the all-frame raw source list for FOV %d.', index);
        end
        clear reference;
    end
end
end
