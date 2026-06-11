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

`pipeline2` can discover registered plugins dynamically. The pipeline template should keep the module `type` and package name, while the local DetecDiv preferences remember where external plugin roots are installed on the current machine.

