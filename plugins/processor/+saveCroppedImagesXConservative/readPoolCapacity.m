function plan = readPoolCapacity(cpuLimit, availableBytes, blockBytes, frameBytes, roiBytes, cachedBytes, driftBytes, frameCount)
% Bound process workers after reserving the legacy client's image buffers.
validateattributes(cpuLimit, {'numeric'}, {'scalar','integer','positive','finite'});
validateattributes(availableBytes, {'numeric'}, {'scalar','nonnegative','finite'});
validateattributes([blockBytes frameBytes roiBytes cachedBytes driftBytes], ...
    {'numeric'}, {'vector','nonnegative','finite'});
validateattributes(frameCount, {'numeric'}, {'scalar','integer','positive','finite'});
% The client can hold the raw block, parfor receive buffers and drift copy.
% Cropping/writing can hold two complete ROI sequences. Pool workers only
% read one frame, but receive the FOV/project handle graph and its image cache.
clientBytes = 3*blockBytes + 2*roiBytes + driftBytes;
workerBytes = 2*2^30 + 4*frameBytes + cachedBytes;
memoryWorkers = floor(max(0, availableBytes-clientBytes)/workerBytes);
count = min([cpuLimit frameCount memoryWorkers]);
if count < 1
    error('saveCroppedImagesXConservative:ReadPoolMemory', ...
        ['Raw block/crop/drift reserve %.2f GiB plus one read worker %.2f GiB ' ...
         'exceeds usable job RAM %.2f GiB. Reduce cut or request more RAM.'], ...
        clientBytes/2^30, workerBytes/2^30, availableBytes/2^30);
end
plan = struct('workers',count,'cpuLimit',cpuLimit,'availableBytes',availableBytes, ...
    'clientReserveBytes',clientBytes,'workerReserveBytes',workerBytes, ...
    'blockBytes',blockBytes,'frameBytes',frameBytes,'framesPerBlock',frameCount);
end
