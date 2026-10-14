function [paramout, dataout, imageout] = process(param, roiobj, ctx)
% Pipeline adapter around the unchanged Xtra full-channel function.
if nargin < 3 || isempty(ctx)
    ctx = struct();
elseif ~isstruct(ctx)
    ctx = struct('frames', ctx);
end
if nargin == 0 || isempty(param)
    paramout = xtraFullChannelsConservative.setparam();
    dataout = [];
    imageout = [];
    return;
end
if isfield(param, 'parallel') && logical(param.parallel)
    error('xtraFullChannelsConservative:ParallelNotSupported', ...
        'Disable processor parallel execution for the original GPU-based function.');
end

if isempty(roiobj.image)
    roiobj.load;
end
if isempty(roiobj.image) || size(roiobj.image, 3) < 6
    availableChannels = 0;
    if ~isempty(roiobj.image)
        availableChannels = size(roiobj.image, 3);
    end
    error('xtraFullChannelsConservative:InsufficientChannels', ...
        ['The original Xtra function requires at least six ROI image channels ' ...
         '(channels 1-6); ROI %s has %d.'], char(string(roiobj.id)), availableChannels);
end
[temporalClassi, temporalNet, pixelClassi, pixelNet] = ...
    xtraFullChannelsConservative.loadLegacyInputs();
xtraFullChannelsConservative.combine_plus_classi_Xtra_full_channels_7( ...
    roiobj, temporalClassi, temporalNet, pixelClassi, pixelNet);

% The legacy function saves and clears the ROI, then reloads results only.
% Reload the complete ROI so processData can persist its returned channels.
roiobj.load;
if isempty(roiobj.image)
    error('xtraFullChannelsConservative:ReloadFailed', ...
        'The original function completed but ROI %s could not be reloaded.', char(string(roiobj.id)));
end
paramout = struct();
paramout.saveChannels = {'seg'};
% Xtra writes quantitative outputs to the legacy roi.results structure.
% Do not return roi.data here: processData interprets it as dataseries output.
dataout = [];
imageout = roiobj.image;
end
