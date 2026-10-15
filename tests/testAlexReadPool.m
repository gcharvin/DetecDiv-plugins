function tests = testAlexReadPool
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'plugins','processor'));
if isempty(which('shallow'))
    addpath(genpath(fullfile(fileparts(root),'DetecDiv')));
end
testCase.TestData.previousThreads = maxNumCompThreads;
testCase.TestData.previousCpu = getenv('DETECDIV_HUB_WORKER_CPU_LIMIT');
testCase.TestData.previousMemory = getenv('DETECDIV_HUB_WORKER_MEMORY_LIMIT_MB');
maxNumCompThreads(2);
setenv('DETECDIV_HUB_WORKER_CPU_LIMIT','2');
setenv('DETECDIV_HUB_WORKER_MEMORY_LIMIT_MB','24576');
end

function teardownOnce(testCase)
maxNumCompThreads(testCase.TestData.previousThreads);
setenv('DETECDIV_HUB_WORKER_CPU_LIMIT',testCase.TestData.previousCpu);
setenv('DETECDIV_HUB_WORKER_MEMORY_LIMIT_MB',testCase.TestData.previousMemory);
end

function testCpuAndFrameCeilings(testCase)
plan = saveCroppedImagesXConservative.readPoolCapacity(8,64*2^30,1,1,1,0,0,88);
verifyEqual(testCase,plan.workers,8);
plan = saveCroppedImagesXConservative.readPoolCapacity(2,64*2^30,1,1,1,0,0,88);
verifyEqual(testCase,plan.workers,2);
plan = saveCroppedImagesXConservative.readPoolCapacity(8,64*2^30,1,1,1,0,0,3);
verifyEqual(testCase,plan.workers,3);
end

function testLargeBlocksReduceWorkersWithinSharedMemory(testCase)
frame = 2048*2048*6*2;
plan = saveCroppedImagesXConservative.readPoolCapacity(8,18*2^30, ...
    frame*88,frame,171*171*6*517*2,0,2048*2048*128,88);
verifyLessThan(testCase,plan.workers,8);
verifyGreaterThanOrEqual(testCase,plan.workers,2);
verifyLessThanOrEqual(testCase,plan.clientReserveBytes + ...
    plan.workers*plan.workerReserveBytes,plan.availableBytes);
verifyError(testCase,@() saveCroppedImagesXConservative.readPoolCapacity( ...
    8,4*2^30,frame*88,frame,0,0,0,88), ...
    'saveCroppedImagesXConservative:ReadPoolMemory');
end

function testCachedProjectImagesCountAgainstEveryWorker(testCase)
plain = saveCroppedImagesXConservative.readPoolCapacity(8,18*2^30,1,1,1,0,0,88);
cached = saveCroppedImagesXConservative.readPoolCapacity(8,18*2^30,1,1,1,4*2^30,0,88);
verifyLessThan(testCase,cached.workers,plain.workers);
end

function testExplicitPoolAndHistoricalExtraction(testCase)
assumeTrue(testCase,logical(license('test','Distrib_Computing_Toolbox')));
assumeEmpty(testCase,gcp('nocreate'),'Do not alter a pre-existing test runner pool.');
root = tempname; mkdir(root);
filesCleanup = onCleanup(@() removeFixture(root)); %#ok<NASGU>
[project,f] = fixture(root);
ctx = struct('sel',struct('frames',1:5),'run',struct('runId',['read_pool_' char(java.util.UUID.randomUUID)]));
param = struct('cut',2);
settings = parallel.Settings; autoCreate = settings.Pool.AutoCreate;
plan = saveCroppedImagesXConservative.planReadPool(project,ctx,param,1);
verifyEqual(testCase,plan.cpuLimit,2);
verifyEqual(testCase,plan.workers,2);
[guard,info] = saveCroppedImagesXConservative.openReadPool(plan);
verifyEqual(testCase,info.workers,2);
verifyTrue(testCase,info.owned);
verifyEqual(testCase,numel(unique(info.workerPids)),2);
verifyEqual(testCase,info.workerThreads,[1 1]);
pool = gcp('nocreate');
conflict = plan; conflict.workers = 1;
verifyError(testCase,@() saveCroppedImagesXConservative.openReadPool(conflict), ...
    'saveCroppedImagesXConservative:ReadPoolConflict');
verifyTrue(testCase,isvalid(pool));
pids = zeros(1,8); images = cell(1,8);
parfor i = 1:8
    images{i} = f.readImage(1+mod(i-1,5),1);
    pids(i) = feature('getpid');
    pause(0.1);
end
verifyEqual(testCase,numel(unique(pids)),2);
for i=1:8
    verifyEqual(testCase,images{i},uint16((101+mod(i-1,5))*ones(16)));
end
% Run the historical multi-block extraction with the explicit pool. No GPU
% is needed for this TIFF/crop test; real drift behavior remains unchanged.
saveCroppedImagesXConservative.saveCroppedImages_X(project,'cut',2,'correctdrift',false);
loaded = load(fullfile(root,'project','position','im_r1.mat'),'roiobj');
verifyEqual(testCase,size(loaded.roiobj.image),[8 8 6 5]);
for c=1:6
    for t=1:5
        verifyEqual(testCase,loaded.roiobj.image(:,:,c,t),uint16((100*c+t)*ones(8)));
    end
end
% Reusing a caller-owned pool must not close or reconfigure it.
[borrowed,borrowedInfo] = saveCroppedImagesXConservative.openReadPool(plan);
verifyFalse(testCase,borrowedInfo.owned);
clear borrowed
verifyTrue(testCase,isvalid(pool));
clear guard
verifyEmpty(testCase,gcp('nocreate'));
verifyEqual(testCase,settings.Pool.AutoCreate,autoCreate);
end

function testOwnedPoolClosesWhenExtractionRaises(testCase)
assumeTrue(testCase,logical(license('test','Distrib_Computing_Toolbox')));
assumeEmpty(testCase,gcp('nocreate'));
plan = saveCroppedImagesXConservative.readPoolCapacity(1,8*2^30,1,1,1,0,0,2);
verifyError(testCase,@() failInsidePool(plan),'AlexReadPoolTest:ExpectedFailure');
verifyEmpty(testCase,gcp('nocreate'));
end

function failInsidePool(plan)
guard = saveCroppedImagesXConservative.openReadPool(plan); %#ok<NASGU>
error('AlexReadPoolTest:ExpectedFailure','Exercise cleanup after an extraction failure.');
end

function [p,f] = fixture(root)
raw = fullfile(root,'raw');mkdir(raw);
p = shallow();p.io=struct('path',[root filesep],'file','project');
f = fov();f.id='position';f.channel=arrayfun(@(c)sprintf('ch%d',c),1:6,'UniformOutput',false);
f.frames=5*ones(1,6);f.interval=ones(1,6);
f.display.binning=ones(1,6);f.srcpath=repmat({raw},1,6);
for c=1:6
    for t=1:5
        name=sprintf('c%d_t%d.tif',c,t);imwrite(uint16((100*c+t)*ones(16)),fullfile(raw,name));
        f.srclist{c}(t)=dir(fullfile(raw,name));
    end
end
r=roi('r1',[2 2 8 8]);r.path=fullfile(root,'project',f.id);mkdir(r.path);
f.roi=r;p.fov=f;
end

function removeFixture(root)
assert(startsWith(root,tempdir,'IgnoreCase',true),'Unexpected cleanup path.');
rmdir(root,'s');
end
