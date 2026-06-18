# bestFocusPlane

DetecDiv processor plugin that keeps the original ROI z-stack channels and adds one derived best-focus channel.

For each ROI and each frame, the plugin:

1. reads the selected ROI image channels as ordered z planes,
2. computes a Laplacian-variance focus score for each z plane,
3. optionally smooths the score along z,
4. selects the best z independently for that ROI and frame,
5. writes a new ROI channel, by default `DIC_focus`,
6. writes a temporal dataseries, by default `DIC_focus_best_z`.

The dataseries has one row per frame and stores `zBest`, `zBestChannelIndex`,
`zBestChannelName`, summary scores, and the full raw/smoothed focus curves in
`focusCurveRaw` and `focusCurveSmooth`.

The intended pomegranate workflow is:

1. `roiExtract`: extract and keep all `DIC_Z###` channels,
2. `bestFocusPlane`: add `DIC_focus`,
3. `cnn_lstm`: train/infer division timing from `DIC_focus`.
