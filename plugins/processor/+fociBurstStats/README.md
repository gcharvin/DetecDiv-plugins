# fociBurstStats external processor

This is a DetecDiv processor package kept outside the main DetecDiv tree.

Load it in MATLAB:

```matlab
run('C:\Users\Gilles Charvin\SynologyDrive\manuel\analysis\load_fociBurstStats_plugin.m')
which fociBurstStats.process
```

In pipeline2, use a processor node with package name `fociBurstStats`.

Main outputs:

- ROI dataseries: `foci_burst_stats` by default, containing `PredFoci` and `TrainFoci` 0/1 frame traces.
- Excel workbook: `<project folder>\<runId>\foci_burst_stats.xlsx` by default.
- Sheets: `summary`, `per_roi`, `raw_frames`, `raw_intervals`, `hist_bout`, `hist_inter_onset`.
- Optional PNG figures: `hist_bout.png`, `hist_inter_onset.png`.

Important parameters:

- `groupID`: classification dataseries groupid to read. Empty means first classification dataseries.
- `framePeriod`, `timeUnit`: temporal calibration.
- `nBins`, `normalization`, `xLim`: histogram control.
- `outputDir`, `workbookName`, `runId`: run output location. The Excel workbook is written directly under `outputDir`; leave `outputDir` empty to use the DetecDiv project folder.
- `resetRun`: delete previous state for this run before the first ROI of a session.

For direct non-pipeline use:

```matlab
load_fociBurstStats_plugin
[stats, perROI, raw] = fociBurstStats.runOnRois(roiList, ...
    'groupID', 'cnnlstm_2', 'framePeriod', 1, 'timeUnit', 'min');
```
