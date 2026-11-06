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
`legacy_viterbi`. The initial 2026-11-05 experimental datg2 templates used
locked depth, rightward depth >=0.60 and output names suffixed `_locked`.
Those local templates were superseded by the calibrated `trap_back` policy
below after checking the different movie orientations.
Use a new run; existing scientific channels are preserved. This normalized
ROI region is an explicit geometric approximation, not automatic trap-wall
segmentation. Review/calibrate it for differently cropped or rotated traps.

### Separate spatial selection from identity continuity (2026-11-06)

`targetSelectionMode=trap_back` uses the EXISTING `anchorMode` setting
(`left`, `right`, `up`, `down`) as its single orientation source. The saved
`trapDepthDirection` applies only to the older `locked_depth` policy. Check
the raw trap geometry per movie: the local low-intensity legacy movie has
its narrow back on the right; the datg2 single-plane movies have it on the
left. Intensity itself must never determine orientation.

This mode requires explicit normalized `targetCavityBounds=[x y width height]`.
Candidates must have their centroid and at least `targetMinCavityFraction`
(default 0.5) of their pixels inside that rectangle. Their back-facing pole
(90th percentile depth) must reach the rear `targetBackFraction` (0.30).
Among eligible instances the deepest centroid wins, independently of label
number. Near-ties abstain. Unlike a centroid-only initialization gate, this
allows a long mother to touch the back even when its centre is elsewhere.

Selection is evaluated each frame, so a three-frame segmentation failure
does not suppress the rest of the movie. Missing masks remain empty; no
interpolation or synthetic mask is written. Identity continuity is reported
separately in `targetIdentitySegment` and `targetLinkState`. A split, a long
gap or a geometrically incompatible observation starts a new segment; it is
not asserted to be the same biological cell. This is a resident-cell policy,
not a mother-lineage decoder. `stopAtSplit` does not truncate this mode's
resident observations; historical modes retain their behavior.

Evaluate segmentation against reviewed instance masks, selection against
the intended cell conditional on that cell being segmented, and septum
scores on a separate reference mask. A reviewed instance split at a septum
can put the septum on the instance BORDER: the current inside-mask stripe
detector then cannot observe it. A union of two masks may be used as an
explicit diagnostic, never as an unmarked replacement of GT or inference.
Temporal segment IDs and increased coverage are not accuracy measurements.

### Exclude unreliable focus frames (opt-in, 2026-11-06)

`focusQualityEnabled=true` evaluates raw images independently of Cellpose
masks, before target selection, split decisions and septum scoring. Its
reference uses the full supplied ROI movie, including when the requested
processing frames are sparse. Fine detail is Laplacian variance; edge
strength is the 90th percentile gradient magnitude after Gaussian smoothing.
Each image is normalized by its 1st–99th intensity percentiles before these
measurements. Both measures are divided by their within-movie median.

The default joint rejection condition is `focusDetailRatioThreshold=0.5`
AND `focusEdgeRatioThreshold=0.92`. These thresholds were calibrated on the
local low-intensity control and datg2_s3; they are not independently validated
focus ground truth. `focusRegions=[.20 .23 .66 .18; .20 .70 .66 .15]` selects
stable trap-wall bands in these crops. Calibrate those normalized rectangles
for differently positioned traps. A nonfinite or zero-contrast image is
always rejected. With fewer than `focusMinReferenceFrames=5` usable images,
relative rejection is disabled and the diagnostic states insufficient
reference. A uniformly defocused movie cannot be recognized by this relative
criterion. Noise can also affect fine-detail measures, hence the joint gate.

Excluded frames retain their original indices, but have an empty OUTPUT
target mask, `trackValid=false`, a NaN septum score and no septum detection.
The source raw and Cellpose instance channels are preserved. The next usable
image is evaluated normally; masks and scores are never interpolated. Focus
exclusions do not consume the reliable-observation gap budget of `trap_back`
or `locked_depth`. A geometric match after a long focus exclusion does not
by itself prove biological identity. No detector threshold or stripe scoring
formula changes with this option.

Diagnostics add `focusRejected`, `focusDetailRatio`, `focusEdgeRatio` and
`focusRejectReason` to the score series, with full reference/region metadata.
Selection state 5 denotes focus rejection. The option defaults to false for
historical compatibility. Use distinct output names for comparisons; the
local datg2 templates use `_back_focus_20261106` and enable the filter.
Tests cover exclusion, recovery, split handling, affine intensity invariance,
sparse requests, all-invalid images and disabled-mode compatibility.

### Septum on a newly split instance boundary (opt-in, 2026-11-06)

`septumBoundarySupportEnabled=true` separates the selected-cell segmentation
from its septum scoring region. Within two reliable missing-frame intervals,
an area loss to 30–80% of a previous selected mask can trigger inspection of
CURRENT instances. A unique partner must occupy at least 20% of the former
parent, overlap it by >=75% of its own area, recover >=75% of the parent with
the selected instance, and have a combined area within 75–135% of the parent.
The two instances must be at most three pixels apart; a two-pixel closing
fills their internal boundary. Only that pair is scored with the unchanged
transverse detector and threshold. Pre-existing neighbours without an observed
common parent are never merged. This evidence concerns an existing septum
at a split; it does not establish its first biological appearance.

The selected mask and original Cellpose labels are unchanged. A separate
`<outputMaskChannelName>_septum_support` channel exposes the actual scoring
region. `septumOriginalScore` preserves the single-instance score;
`septumSupportState`, `septumSupportParentFrame`, `septumSupportPartnerLabel`
and `septumScorable` document the decision. If the area loss suggests a
partial segmentation but the second current instance is absent or ambiguous,
the processor abstains (NaN, scorable=false), rather than copying the former
mother or declaring the visible septum absent. Focus-rejected images remain
excluded. Defaults stay disabled for historical compatibility.

Human image choices are presence labels at image level. A septum on another
cell closer to the opening is not a false negative for the closed-back target.
Distinguish absent target segmentation, spatial target selection, and septum
scoring; do not relax the target gate just to fit image-level choices.
