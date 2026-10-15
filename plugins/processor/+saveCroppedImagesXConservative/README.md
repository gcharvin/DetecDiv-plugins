# saveCroppedImagesXConservative

This package contains the original `saveCroppedImages_X.m` function from
Downloads with the required Hub adaptations: an optional ROI-index selector
and initialization of channel display arrays before they are rebuilt.
`process.m` adapts the legacy project/FOV function to pipeline2. Project and
FOV/ROI/frame selections come from run context; the module has no required data
input. The ROI selector leaves unselected ROI paths untouched. Frame indexing
supports all frames or a prefix beginning at frame 1; the wrapper rejects
other selections rather than changing the legacy behavior. Keep processor
parallel execution disabled.

The adapter explicitly opens a process pool before the historical frame-reading
`parfor`, including when MATLAB `Pool.AutoCreate` is disabled. It uses the lower
of the job CPU limit and MATLAB thread limit, then reduces process count to fit
remaining job RAM (including cgroup limits), the raw block/crop/drift buffers,
and each worker's MATLAB process and serialized image-cache overhead. The
matching Hub attempt payload also caps CPU/RAM admission when a Windows
worker's static capacity is larger than this particular job's allocation. The fixed
`cut=88` and all scientific calculations remain unchanged. Insufficient RAM or
an incompatible existing pool is reported before extraction, never silently
treated as parallel execution. Pool workers use one compute thread each.
The pool's actual PIDs/threads are logged; a pool created by the adapter is closed
on success or failure. A compatible pre-existing pool is preserved. Global
MATLAB preferences and the universal `roi.save` implementation are untouched.
The wrapper code is highlighted `ADAPTATION PARALLEL POOL 2026-10-15`.

The execution contract declares `imagesToRoi`: dry-run validation projects the
raw source channels through this processor to downstream analysis, including
projects whose unextracted ROIs still show only `Channel 1`. This requires a
DetecDiv validator supporting processor `imagesToRoi` transfers. The six-channel
analysis requirement remains enforced; no acquisition names are hardcoded.

An empty run frame selection means all raw frames even when an existing ROI
HDF5 contains only a short preview. The adapter first hydrates channel 1's
raw file list through `fov.readImage` if a lightweight project has not loaded
it yet, before the legacy routine counts all frames. Intermediate extraction blocks reload
their own legacy MAT output, so an older HDF5 cannot overwrite earlier blocks.
An optional pipeline `cut` parameter is forwarded to the existing historical
argument of the same name. It limits frames per raw block, independently of
the total run frame selection. The fixed default is now 88 frames per block
for the 24-GiB worker allocation, after the 176-frame run stalled under memory
pressure. Both the pipeline parameter
defaults and the legacy script use this value; all 517 frames are processed
as five 88-frame blocks plus a final 77-frame block. The legacy default-size change is marked
`ADAPTATION MEMOIRE 2026-10-14`; allocations, cleanup, scientific calculations,
and universal ROI saving are unchanged. The adapter forwarding code is marked
`ADAPTATION PIPELINE 2026-10-14`.

The function calls the bundled `computeDrift_X.m` helper through this package.
It retains the original crash recovery, project save, output-file, and drift
calculation behavior.
