function legacyRoi = loadLegacyOutput(shallowObj, roiobj)
% Load the exact MAT artifact written by saveCroppedImages_X.
matPath = '';
try
    if ~isempty(roiobj.path)
        candidate = fullfile(char(string(roiobj.path)), ['im_' char(string(roiobj.id)) '.mat']);
        if exist(candidate, 'file') == 2
            matPath = candidate;
        end
    end
catch
end
if isempty(matPath)
    fovId = '';
    try
        if isa(roiobj.parent, 'fov'), fovId = char(string(roiobj.parent.id)); end
    catch
    end
    if isempty(fovId)
        for i = 1:numel(shallowObj.fov)
            if any(strcmp({shallowObj.fov(i).roi.id}, char(string(roiobj.id))))
                fovId = char(string(shallowObj.fov(i).id));
                break;
            end
        end
    end
    if isempty(fovId)
        error('saveCroppedImagesXConservative:MissingFovForOutput', ...
            'Could not resolve the FOV output folder for ROI %s.', char(string(roiobj.id)));
    end
    projectRoot = [char(string(shallowObj.io.path)) char(string(shallowObj.io.file))];
    matPath = fullfile(projectRoot, fovId, ['im_' char(string(roiobj.id)) '.mat']);
end
if exist(matPath, 'file') ~= 2
    error('saveCroppedImagesXConservative:LegacyOutputMissing', ...
        'The original function did not create its expected ROI output: %s', matPath);
end
loaded = load(matPath, 'roiobj');
if ~isfield(loaded, 'roiobj') || ~isa(loaded.roiobj, 'roi')
    error('saveCroppedImagesXConservative:InvalidLegacyOutput', ...
        'The file written by the original function does not contain a ROI object: %s', matPath);
end
legacyRoi = loaded.roiobj;
end
