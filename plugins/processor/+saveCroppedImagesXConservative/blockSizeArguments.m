function args = blockSizeArguments(param)
% ADAPTATION PIPELINE 2026-10-14: pass the historical 'cut' option unchanged.
args = {};
if ~isfield(param,'cut') || isempty(param.cut), return; end
value = param.cut;
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
        ~isfinite(value) || value<1 || value~=fix(value)
    error('saveCroppedImagesXConservative:InvalidBlockSize', ...
        'cut must be a positive integer number of frames per raw block.');
end
args = {'cut',double(value)};
end
