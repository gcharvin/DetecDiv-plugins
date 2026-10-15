function plan = planReadPool(project, ctx, param, fovIndices)
% Plan the legacy frame-reading pool inside this job's CPU and RAM limits.
cpuLimit = max(1, floor(double(maxNumCompThreads)));
environmentCpu = str2double(getenv('DETECDIV_HUB_WORKER_CPU_LIMIT'));
if isfinite(environmentCpu) && environmentCpu >= 1
    cpuLimit = min(cpuLimit, floor(environmentCpu));
end
[available, note] = roiExtract.availableMemoryBytes();
memoryMB = str2double(getenv('DETECDIV_HUB_WORKER_MEMORY_LIMIT_MB'));
% The native Windows worker can have a larger static capacity than this job.
% Hub starts MATLAB in its attempt directory. Only trust the payload whose
% run ID matches this invocation; never consume another/manual run's file.
allocation = matchingJobAllocation(ctx,param);
if isfield(allocation,'cpu_cores') && allocation.cpu_cores >= 1
    cpuLimit = min(cpuLimit,floor(double(allocation.cpu_cores)));
end
if isfield(allocation,'memory_mb') && allocation.memory_mb > 0
    if isfinite(memoryMB) && memoryMB > 0
        memoryMB = min(memoryMB,double(allocation.memory_mb));
    else
        memoryMB = double(allocation.memory_mb);
    end
end
% Subtract the client from a static cap as well as respecting remaining
% cgroup RAM. This matters on Windows, which has no Linux service cgroup.
resident = 0;
if ispc
    current = System.Diagnostics.Process.GetCurrentProcess();
    resident = double(current.WorkingSet64);
else
    token = regexp(fileread('/proc/self/status'),'(?m)^VmRSS:\s+(\d+)\s+kB','tokens','once');
    if ~isempty(token), resident = str2double(token{1})*1024; end
end
if isfinite(memoryMB) && memoryMB > 0
    available = min(available,0.8*max(0,memoryMB*2^20-resident));
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
plan.jobAllocation = allocation;
fprintf(['[Alex extraction] Read-pool plan: CPU ceiling %d, usable RAM %.2f GiB, ' ...
    'client reserve %.2f GiB, %.2f GiB/read worker: admitted %d. %s\n'], ...
    plan.cpuLimit,available/2^30,plan.clientReserveBytes/2^30, ...
    plan.workerReserveBytes/2^30,plan.workers,note);
end

function allocation = matchingJobAllocation(ctx,param)
allocation = struct(); runId = '';
if isfield(param,'runId') && ~isempty(param.runId)
    runId = char(string(param.runId));
elseif isfield(ctx,'run') && isfield(ctx.run,'runId')
    runId = char(string(ctx.run.runId));
end
file = fullfile(pwd,'pipeline_run_job.json');
if isempty(runId) || ~isfile(file), return; end
payload = jsondecode(fileread(file));
if isfield(payload,'run_request') && isfield(payload.run_request,'run_id') && ...
        strcmp(char(string(payload.run_request.run_id)),runId) && ...
        isfield(payload,'x_hub_resource_allocation')
    % jsondecode makes the leading underscore in the Python key a valid
    % MATLAB field name: _hub_resource_allocation -> x_hub_resource_allocation.
    allocation = payload.x_hub_resource_allocation;
end
end
