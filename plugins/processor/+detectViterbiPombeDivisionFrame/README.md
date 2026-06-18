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
