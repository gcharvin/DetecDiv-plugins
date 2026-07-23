# detecdivPomegranate

DetecDiv processor plugin that reproduces the useful Pomegranate measurement stage in a pipeline-friendly way.

The processor consumes:

- a DIC/BF z-stack channel set for the ROI
- the `cell_of_interest` mask channel produced by `detectViterbiPombeDivisionFrame`
- the septum score dataseries produced by `detectViterbiPombeDivisionFrame`

It writes:

- Pomegranate-compatible `*_Results_Full.csv` files and the optional Excel workbook. These are the legacy-style tabular outputs.
- The workbook contains a cumulative `summary` sheet with one row per ROI, a cumulative `parameters` sheet with the reconstruction settings and provenance for each ROI, and one z-slice detail sheet per ROI. Detail-sheet names retain the end of the ROI identifier because Excel limits worksheet names to 31 characters.
- `cell_information`, a non-temporal dataseries whose `.data` table stores a compact DetecDiv summary and whose `userData` contains enriched Pomegranate-like morphology/cytometry measurements, the reconstructed 3D mask, QC images, and artifact paths.
- ROI-local PNG QC artifacts: `*_pomegranate_qc_overlay.png` and `*_pomegranate_qc_summary.png`.
- A workbook-local PNG mosaic, `detecdiv_pomegranate_mosaic.png`, assembled from one annotated tile per processed ROI. Each tile shows the best-Z raw plane, segmented contour, ellipse fit, major/minor axes, ROI id, frame, best-Z plane, and reconstructed volume in pixels cubed.

The 3D reconstruction follows the ImageJ Pomegranate idea: clean the mid-plane mask, compute a distance transform, skeletonize it to obtain a medial axis with local radii, then reconstruct each z-slice as the union of disks with radius `sqrt(r^2 - dz^2)`.
