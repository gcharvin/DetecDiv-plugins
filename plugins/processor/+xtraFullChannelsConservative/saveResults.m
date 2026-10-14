function file = saveResults(roiobj)
% Persist the legacy output explicitly; roi.save's image/data contract stays intact.
if isempty(roiobj.path) || ~isfolder(roiobj.path)
    error('xtraFullChannelsConservative:ResultsPathMissing', ...
        'Cannot save results for ROI %s: its output directory is unavailable.', roiobj.id);
end
results = roiobj.results; %#ok<NASGU>
if ~isstruct(results) || ~isscalar(results) || isempty(fieldnames(results))
    error('xtraFullChannelsConservative:ResultsMissing', ...
        'Analysis produced no legacy results for ROI %s.', roiobj.id);
end
file = fullfile(roiobj.path, ['results_' roiobj.id '.mat']);
staged = [tempname(roiobj.path) '.mat'];
cleanup = onCleanup(@() removeStaged(staged)); %#ok<NASGU>
save(staged, 'results', '-v7.3');
verified = load(staged, 'results');
if ~isfield(verified, 'results') || ~isequaln(verified.results, results)
    error('xtraFullChannelsConservative:ResultsVerificationFailed', ...
        'Verification failed for ROI %s; existing results were preserved.', roiobj.id);
end
[ok, message] = movefile(staged, file, 'f');
if ~ok
    error('xtraFullChannelsConservative:ResultsWriteFailed', ...
        'Cannot install results for ROI %s: %s', roiobj.id, message);
end
end

function removeStaged(file)
if isfile(file), delete(file); end
end
