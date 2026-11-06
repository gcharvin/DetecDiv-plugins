# DetecDiv Plugins

External DetecDiv modules live here so they can be versioned without growing the main DetecDiv repository.

The expected layout is:

```text
plugins/
  processor/
    +packageName/
      process.m
      setparam.m
      executionSpec.m
  classifier/
    +packageName/
      classify.m
      setparam.m
      executionSpec.m
```

Add the plugin repository to DetecDiv from MATLAB:

```matlab
detecdiv_plugins_register_root('C:\Users\Gilles Charvin\Documents\DetecDiv-plugins')
detecdiv_plugins_addpath
detecdiv_plugins_list
```

Browse installed plugins and their contracts:

```matlab
detecdiv_plugins_browser
```

`pipeline2` can discover registered plugins dynamically. The pipeline template should keep the module `type` and package name, while the local DetecDiv preferences remember where external plugin roots are installed on the current machine.

For the Pombe septum processor, replace a bundled code binding with the
installed checkout (after updating it from GitHub):

```matlab
addpath('C:/path/to/DetecDiv-plugins')
detecdiv_pombe_septum_relink('C:/path/to/pipeline/pipeline.json')
```

This saves a template backup and enables `transverse2d`. Create a new local
pipelineRun from the updated template. The run folder receives the Excel
frame summary, a segmentation mosaic per FOV, and runtime code provenance.

Pombe 0.5.0 adds opt-in focus exclusion, calibrated trap-back selection, and
scoring at the interface of recently split masks. For the datg2 single-plane
crops (back on the LEFT), activate these explicitly:

```matlab
detecdiv_pombe_septum_relink('C:/path/to/pipeline/pipeline.json', [], ...
    'TrapBackDirection','left','CavityBounds',[.24 .40 .60 .30], ...
    'EnableFocusFilter',true,'EnableBoundarySupport',true, ...
    'OutputSuffix','_pombe050');
```

Open the saved template again and create a **new** run. A backup of the old
template is saved. Old runs, segmentation inputs and existing result names are
preserved. Run-profile overrides receive the same settings. The helper alone,
without the named options, retains previous target/focus policies.

Check orientation and crop on each movie. The low-intensity legacy movie has
its back on the RIGHT and uses `[.20 .36 .55 .33]`; do not apply the datg2
calibration to all datasets. Focus bands also require checking on other crops.
Inspect raw data, instance masks and the separate `_septum_support` scoring
channel. An incomplete segmentation is an abstention, not proof of absence.
The update does not guarantee that granules are never confused with septa or
that the exported first detection equals biological onset. The known old
ROI1/frame22 missing-half and weak-contrast case remains unresolved. Validation
so far consists of regression tests and local sequence inspection, not an
independent sensitivity/specificity study. See the processor README for details.
