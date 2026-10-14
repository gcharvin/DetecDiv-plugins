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
An optional pipeline `cut` parameter is forwarded to the existing historical
argument of the same name. It limits frames per raw block, independently of
the total run frame selection. The fixed default is now 176 frames per block
(`floor(2*265/3)`) for the 24-GiB worker allocation. Both the pipeline parameter
defaults and the legacy script use this value; all 517 frames are processed
as 176 + 176 + 165. The legacy default-size change is marked
`ADAPTATION MEMOIRE 2026-10-14`; allocations, cleanup, scientific calculations,
and universal ROI saving are unchanged. The adapter forwarding code is marked
`ADAPTATION PIPELINE 2026-10-14`.

The function calls the bundled `computeDrift_X.m` helper through this package.
It retains the original crash recovery, project save, output-file, and drift
calculation behavior.
