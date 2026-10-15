function plan = planReadPool(project, ctx, param, fovIndices)
% Plan the legacy frame-reading pool inside this job's CPU and RAM limits.
cpuLimit = max(1, floor(double(maxNumCompThreads)));
environmentCpu = str2double(getenv('DETECDIV_HUB_WORKER_CPU_LIMIT'));
if isfinite(environmentCpu) && environmentCpu >= 1
    cpuLimit = min(cpuLimit, floor(environmentCpu));
end
[available, note] = roiExtract.availableMemoryBytes();
% Windows has no Linux service cgroup: subtract the client's current working
% set from the inherited job cap before admitting extra MATLAB processes.
memoryMB = str2double(getenv('DETECDIV_HUB_WORKER_MEMORY_LIMIT_MB'));
if ispc && isfinite(memoryMB) && memoryMB > 0
    current = System.Diagnostics.Process.GetCurrentProcess();
    available = min(available, 0.8*max(0, memoryMB*2^20-double(current.WorkingSet64)));
end
args = saveCroppedImagesXConservative.blockSizeArguments(param);
if isempty(args)
    defaults = saveCroppedImagesXConservative.setparam(); cut = defaults.cut;
else
    cut = args{2};
end
frames = saveCroppedImagesXConservative.selectedFrames(ctx);
cachedBytes = 0;
for i = 1:numel(project.fov)
    for j = 1:numel(project.fov(i).roi)
        image = project.fov(i).roi(j).image; %#ok<NASGU>
        spec = whos('image'); cachedBytes = cachedBytes + spec.bytes;
    end
end
blockBytes = 0; frameBytes = 0; roiBytes = 0; driftBytes = 0; frameCount = 1;
for i = fovIndices(:)'
    f = project.fov(i); image = f.readImage(1,1);
    if isempty(image)
        error('saveCroppedImagesXConservative:ReadPoolProbe', ...
            'Cannot size the read pool: FOV %d reference image is unavailable.',i);
    end
    spec = whos('image'); channels = numel(f.channel);
    pixels = double(size(image,1))*double(size(image,2));
    if isempty(frames) || all(frames == -1)
        totalFrames = numel(f.srclist{1});
    else
        totalFrames = numel(frames);
    end
    count = min(cut,totalFrames);
    frameCount = max(frameCount,count);
    frameBytes = max(frameBytes,double(spec.bytes)*channels);
    % The historical block is uint16 even if a source plane has another type.
    blockBytes = max(blockBytes,2*pixels*channels*count);
    driftBytes = max(driftBytes,128*pixels);
    for j = 1:numel(f.roi)
        rect = double(f.roi(j).value);
        if numel(rect) >= 4
            roiBytes = max(roiBytes,2*rect(3)*rect(4)*channels*totalFrames);
        end
    end
end
plan = saveCroppedImagesXConservative.readPoolCapacity( ...
    cpuLimit,available,blockBytes,frameBytes,roiBytes,cachedBytes,driftBytes,frameCount);
plan.memoryNote = note;
fprintf(['[Alex extraction] Read-pool plan: CPU ceiling %d, usable RAM %.2f GiB, ' ...
    'client reserve %.2f GiB, %.2f GiB/read worker: admitted %d. %s\n'], ...
    plan.cpuLimit,available/2^30,plan.clientReserveBytes/2^30, ...
    plan.workerReserveBytes/2^30,plan.workers,note);
end
