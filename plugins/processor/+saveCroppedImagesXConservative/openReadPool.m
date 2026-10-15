function [guard, info] = openReadPool(plan)
% Explicitly acquire a bounded pool without changing MATLAB preferences.
if exist('parpool','file') ~= 2 || ~license('test','Distrib_Computing_Toolbox')
    error('saveCroppedImagesXConservative:ReadPoolUnavailable', ...
        'Parallel Computing Toolbox is required for the legacy frame-reading pool.');
end
if ~isempty(getCurrentTask)
    error('saveCroppedImagesXConservative:NestedReadPool', ...
        'Run the project-level extraction on the MATLAB client, not inside another pool worker.');
end
pool = gcp('nocreate'); owned = isempty(pool);
if ~owned && (~isa(pool,'parallel.ProcessPool') || pool.NumWorkers > plan.workers)
    error('saveCroppedImagesXConservative:ReadPoolConflict', ...
        ['Existing pool is incompatible with the admitted %d process worker(s). ' ...
         'It was preserved; close or resize it before this extraction.'],plan.workers);
end
if owned
    cluster = parcluster('Processes');
    if plan.workers > cluster.NumWorkers
        error('saveCroppedImagesXConservative:ReadPoolCapacity', ...
            'The local Processes profile supports %d workers; %d were admitted.', ...
            cluster.NumWorkers,plan.workers);
    end
    if isprop(cluster,'NumThreads'), cluster.NumThreads = 1; end
    pool = parpool(cluster,plan.workers);
end
guard = onCleanup(@() closeOwnedPool(pool,owned));
if owned
    % Do not let each process inherit the client's entire eight-CPU allowance.
    fetchOutputs(parfevalOnAll(pool,@maxNumCompThreads,0,1));
end
states = fetchOutputs(parfevalOnAll(pool,@saveCroppedImagesXConservative.readWorkerInfo,1));
if iscell(states), states = [states{:}]; end
if ~all([states.isWorker]) || sum([states.threads]) > plan.cpuLimit
    error('saveCroppedImagesXConservative:ReadPoolThreads', ...
        'Pool worker threads exceed the job CPU ceiling %d.',plan.cpuLimit);
end
info = struct('workers',pool.NumWorkers,'owned',owned,'workerPids',[states.pid], ...
    'workerThreads',[states.threads]);
fprintf('[Alex extraction] Read pool ready: %d process worker(s), PIDs %s, threads %s.\n', ...
    info.workers,mat2str(info.workerPids),mat2str(info.workerThreads));
end

function closeOwnedPool(pool,owned)
if owned && isvalid(pool)
    delete(pool);
end
end
