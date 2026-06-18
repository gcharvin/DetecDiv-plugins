# detecdivPomegranate

DetecDiv processor plugin that reproduces the useful Pomegranate measurement stage in a pipeline-friendly way.

The processor consumes:

- a DIC/BF z-stack channel set for the ROI
- the `cell_of_interest` mask channel produced by `detectViterbiPombeDivisionFrame`
- the septum score dataseries produced by `detectViterbiPombeDivisionFrame`

It writes:

- `cell_information`, a non-temporal dataseries whose `userData` contains Pomegranate-like morphology/cytometry measurements, the reconstructed 3D mask, and QC overlay images.

The 3D reconstruction follows the ImageJ Pomegranate idea: clean the mid-plane mask, compute a distance transform, skeletonize it to obtain a medial axis with local radii, then reconstruct each z-slice as the union of disks with radius `sqrt(r^2 - dz^2)`.
