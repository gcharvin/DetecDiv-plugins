function info = readWorkerInfo()
% Executed on every pool worker to verify actual process/thread admission.
info = struct('pid',feature('getpid'),'threads',maxNumCompThreads, ...
    'isWorker',~isempty(getCurrentTask));
end
