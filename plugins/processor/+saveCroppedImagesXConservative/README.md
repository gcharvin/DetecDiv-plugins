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

An empty run frame selection means all raw frames even when an existing ROI
HDF5 contains only a short preview. Intermediate extraction blocks reload
their own legacy MAT output, so an older HDF5 cannot overwrite earlier blocks.
Raw blocks are recalculated using `roiExtract.availableMemoryBytes` and the
engine's four-buffer planner, including inherited worker/cgroup RAM limits,
ROI load/save buffers, drift workspaces, and the 512 MiB raw-block cap. `cut`
remains an upper bound. Frame readers run in the client, and uint16 buffers
are allocated directly. These memory changes preserve frame order and the
original drift and scientific calculations.

The function calls the bundled `computeDrift_X.m` helper through this package.
It retains the original crash recovery, project save, output-file, and drift
calculation behavior.
