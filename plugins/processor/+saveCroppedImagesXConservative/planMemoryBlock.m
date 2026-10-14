function count = planMemoryBlock(available, pixels, channels, roiBytes, correctDrift, maximum, remaining)
% Reuse the engine's worker/cgroup-aware budget and four-buffer block plan.
% One full legacy ROI plus load/save temporaries stays resident independently
% of the raw block size. Drift workspaces are also a fixed per-FOV cost.
fixedBytes = 3*roiBytes;
if correctDrift, fixedBytes = fixedBytes + 128*pixels; end
frameBytes = 2*pixels*channels; % The original raw/cropped stores are uint16.
count = min(maximum, roiExtract.planFrameBlock(available, frameBytes, fixedBytes, 1, remaining));
end
