# detectViterbiPombeDivisionFrame

DetecDiv processor plugin for the pomegranate `S. pombe` workflow.

The processor consumes:

- a labeled CellposeSAM instance mask channel, typically `results_*_cell`
- a raw/focused DIC channel, typically `DIC_focus`

It writes:

- `cell_of_interest` or another configured binary mask channel
- `pombe_division_profile`, a temporal dataseries with normalized longitudinal intensity profiles
- `pombe_division_score`, a temporal dataseries with septum scores and tracking diagnostics

The tracking step uses a Viterbi path over per-frame segmented objects. The selected mask is intended to stop when the target cell splits, so the downstream intensity-profile analysis remains focused on the cell before separation.

## Septum detection

New nodes default to `septumMethod = 'transverse2d'`. Existing pipeline
snapshots without this setting retain `profile`; select `transverse2d`
explicitly to upgrade them. Exported bundles contain their own plugin copy
and must be refreshed to use the new implementation.

The 2D detector searches transverse lines inside the tracked cell. For each
line it compares intensity point by point to two parallel flanks, at several
pixel distances and orientations. Both flanks must stay inside the mask,
and at least 65% of the transverse samples must have coherent contrast.
The lower-quartile contrast divided by a robust local texture/noise scale
is the score. This reduces the influence of isolated vacuoles, gradual
illumination changes and membrane edges. It supports dark, bright and
absolute polarity; absolute mode requires one consistent polarity per line.
The principal cell axis constrains geometry but is not used to collapse
intensities into a one-dimensional profile.

`septumLineEdgeFraction`, `septumLineMinCoverage`, `septumLineMaxAngle`,
`septumLineFlankOffsets` and `septumMinAspectRatio` control this search.
Offsets are in pixels, so they must be reviewed for different image sampling.
The existing 100-bin intensity profile remains available for comparison.
The score table additionally records `septumProfileScore`, line coverage,
angle, flank distance, normalization scale and endpoints in ROI coordinates.
Parameters and detector version are recorded in the dataseries metadata.

Scores from the two methods have different units; review the detection
threshold using representative annotated movies. The default is 1.5.
The plugin's 2D workbook leaves DivisionFrame empty if no frame passes that
threshold. Legacy profile workbooks retain their maximum-score rule.
`SeptumAppearanceFrame` is the earliest selected frame with a finite score,
a valid track and `septumDetected=true`; it is not the peak frame.
`SeptumPeakFrame` and `SeptumPeakScore` describe the accepted maximum in 2D
mode. `DivisionFrame` remains the compatibility alias for the peak frame.
`DetectionStatus` distinguishes detected, undetermined and missing results.
Downstream `detecdivPomegranate` selection modes have their own policies:
`max_valid_score` still does not use `septumDetected`.

This detector does not repair missing segmentation, select a different
target cell, or validate lineage. A coherent internal structure can still
produce a false positive; visual QC and independent movie validation remain
necessary. Comparisons on the local `single_plane` and `new_project3`
projects are not an independent acquisition validation: their image pixels
in common areas are identical after alignment.

## Automatic QC and runtime provenance (v0.2.1)

Every completed processor batch writes `pombe_division_frames.xlsx` and
one `pombe_septum_mosaic_<FOV>.png` per selected FOV in the run folder.
Tiles use the first accepted septum frame, with the target-cell mask in
orange and the other instance segmentations in light gray. There is no
ellipse. Titles show onset and peak frames. Undetermined ROIs show an
explicitly labeled reference frame, not an inferred division. A JSON
sidecar records the actual frame and status of every tile.

The workbook records `SeptumMethod` and `PluginVersion` for every ROI.
Its `parameters` sheet records the actual process/core/detector paths from
the saved dataseries. The console prints the effective method and output
paths. These are runtime values, not the GUI's advertised default.

To use the installed repository instead of a bundled plugin copy, update
the Git checkout and run `detecdiv_pombe_septum_relink` from the repository
root with the pipeline template path. It backs up the template, replaces
the processor package roots, activates transverse2d, and updates stored
node overrides in template run profiles. Then create a new pipelineRun.

## Optional segmentation tolerance (v0.3.0)

Existing settings retain the immediate split-stop behavior. For a new run,
set `segmentationMaxGapFrames=2` and `splitConfirmationFrames=2` to tolerate
short segmentation failures. An abrupt area loss below
`segmentationGapAreaRatio=0.65` is excluded only when the selected cell
recovers to at least `segmentationRecoveryAreaRatio=0.8` of its pre-gap area
within the configured window, with at least 50% overlap relative to the
smaller mask. Missing observations remain empty with NaN scores: masks are
never interpolated or copied from another frame.
Viterbi can link the observations on either side of such a gap directly,
instead of forcing the trajectory through a small artifact or another cell.
A skip is forbidden when an overlapping, sufficiently large observation of
the pre-gap cell exists in an intermediate frame. Skip edges carry a cost
of 0.25 per missing frame, in addition to the usual continuity cost.

Split/area-loss evidence must persist for the requested number of consecutive
acquired frames. Once confirmed, the mask still stops at the last maternal
frame, not at the later confirmation frame. An unconfirmed event at the end
of a movie does not trigger a terminal stop. Sparse frame selections cannot
stand in for consecutive acquired frames.

The tolerant score table adds `segmentationGapRejected` and
`splitConfirmedFrame`; its metadata records the effective tolerance settings.
Defaults `segmentationMaxGapFrames=0` and `splitConfirmationFrames=1` preserve
the historical numerical behavior and score-table schema. Use distinct
output mask and dataseries names when comparing against a previous run.
This does not reconstruct a missing maternal half at septation or establish
that a resumed trajectory has the correct biological identity.

### Experimental rectified septum prototype (2026-11-05)

`scoreRectifiedSeptum(raw,mask)` rectifies a smooth PCA-guided centreline,
retains transverse support in three bands, and requires contrast at two
smoothing scales. Low-anisotropy masks use image-based orientation search.
It returns the rectified image, median profile, candidate scores and line
coordinates for review. It is not selected by `core` or pipeline defaults.

`rectifiedSeptumEpisodes(frames,scores,positions,angles)` groups spatially
consistent consecutive candidates. Isolated candidates remain explicitly
unconfirmed. Its `confirmed` field denotes temporal support, never human GT.
Thresholds are pilot settings. Highly folded cells, axis changes, brief events
and incomplete tracked masks still require validation. Tests are in
`tests/testPombeRectifiedSeptum.m`.

### Locked trap-back target selection (2026-11-05)

`targetSelectionMode=locked_depth` initializes the deepest eligible centroid
only inside an explicitly configured ROI depth region (`trapDepthDirection`,
`targetMinDepth`). The region must be calibrated from the trap geometry;
it is not inferred from whatever cells Cellpose happened to segment.
Initialization needs a unique overlap-supported candidate in the next frame.
The seed frame is backfilled only after that confirmation. Depth gates
initialization only: the same mother can grow toward the trap mouth.

Identity matching uses intersection / larger mask area (default >=0.5),
area ratio [0.65,1.5], and uniqueness relative to a competing match. Labels
may change. A gap of up to two source frames can recover the same mask;
longer loss is terminal and never restarts on another cell. This conservative
policy cannot distinguish an impostor with identical geometry and does not
infer viability. Ambiguous and missing observations have no score.

The score series adds `targetSelectionState` (0 waiting,1 locked,2 missing,
3 ambiguous,4 lost), `targetSourceLabel`, `targetDepth` and the exact policy
in `userData.targetSelection`. `trackValid` also reflects any downstream
split stop. Old templates without the new mode and global defaults retain
`legacy_viterbi`. The three datg2 templates explicitly enable locked depth,
rightward depth >=0.60, with output names suffixed `_locked`.
Use a new run; existing scientific channels are preserved. This normalized
ROI region is an explicit geometric approximation, not automatic trap-wall
segmentation. Review/calibrate it for differently cropped or rotated traps.
