# singleCellOscillations

DetecDiv processor plugin for Antoine's single-cell fluorescence oscillation analysis.

The plugin consumes ROI dataseries already produced by upstream modules:

- `div_1` or another CNN/LSTM classification dataseries containing `labels`
- `channel_quantification` or another computeMetrics dataseries containing the fluorescence column to analyze

It does not require `computeRLS`. Cycles are detected directly from label transitions, by default `large -> small`, matching the original MATLAB scripts.

## Pipeline Position

Typical order:

```text
dataloader
 -> roiPattern / roiGrid / roiTracked
 -> roiExtract
 -> combineMultipleChannels
 -> cnn_lstm                  outputs div_1
 -> deeplab / cellposeSAM     outputs segmentation
 -> computeMetrics            outputs channel_quantification
 -> singleCellOscillations
```

## Outputs

The plugin writes three ROI dataseries:

- `osc_detrended_trace`, `type="temporal"`: one row per source frame.
- `osc_normalized_cycles`, `type="temporal"`: one row per normalized intra-cycle time point.
- `osc_cycle_metadata`, `type="generation"`: one row per detected cycle candidate, used for durations and QC-style filtering.

The normalized cycles remain temporal because the scientific object is the time-normalized oscillation inside each cell cycle, not a single average value per cycle.

## Key Parameters

```matlab
classification_data = 'div_1'
fluorescence_data = 'channel_quantification'
labelColumn = 'labels'
fluorescenceColumn = 'Ratio_Mean_NoBckg_channel002_z001_channel001_z001_cyto'

transitionFrom = 'large'
transitionTo = 'small'
frameStart = 25
frameEnd = 167
baselineMethod = 'moving_mean'
baselineWindow = 50
normFrames = 100
interpolationMethod = 'linear'
```

If the fluorescence column contains one vector per frame, as computeMetrics can produce for cell masks, `cellValueReducer` controls conversion to a scalar signal. The default is `mean`.
