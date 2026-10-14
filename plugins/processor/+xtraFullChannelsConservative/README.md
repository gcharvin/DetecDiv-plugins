# xtraFullChannelsConservative

`combine_plus_classi_Xtra_full_channels_7.m` retains the supplied analysis
logic. Its pipeline wrapper loads the original four arguments from
`modelPaths.m`, runs one ROI at a time, and reloads the ROI for pipeline
storage. FOV, ROI, and frame selection come from run context; the module has no
separately configured data inputs.

`modelPaths.m` provides absolute model paths for Windows (`X:/`), Linux
(`/data/`), and macOS (`/Volumes/data/`). The four model files must be
available at the matching mount on the Hub host.

The script processes every frame present in each selected ROI image. In the
chained pipeline, extraction first limits the ROI image to the selected frame
prefix. The analysis reads channels 1–3 for the temporal classifier and
segmentation input, and channels 4–6 for fluorescence; it adds segmentation
as channel 7. Legacy helpers `measureRLS_X.m`, `compute_mother_maskedFluo.m`,
`findSEP.m`, and `post.m` are bundled and called through this package. Quantitative outputs remain in the legacy `roi.results` structure; the wrapper returns no dataseries. `saveResults` explicitly writes a verified `results_<roi-id>.mat` sidecar after image saving. DetecDiv's `roi.load` restores this sidecar alongside data; `roi.save` is unchanged. The `seg` image channel is stored in the ROI HDF5 file and replaced without duplicating its channel mapping on reruns. Keep
processor parallel execution disabled.


