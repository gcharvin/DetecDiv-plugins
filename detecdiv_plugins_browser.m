function fig = detecdiv_plugins_browser(varargin)
%DETECDIV_PLUGINS_BROWSER Browse external DetecDiv plugins and contracts.

opts = localParseInputs(varargin{:});
plugins = localDiscoverPlugins(opts.Roots);

fig = uifigure('Name', 'DetecDiv plugins', 'Position', [120 120 1200 760]);
try
    fig.WindowState = 'maximized';
catch
end
main = uigridlayout(fig, [1 2]);
main.ColumnWidth = {380, '1x'};
main.RowHeight = {'1x'};
main.Padding = [12 12 12 12];
main.ColumnSpacing = 14;

left = uigridlayout(main, [3 1]);
left.RowHeight = {24, '1x', 34};
left.ColumnWidth = {'1x'};
left.Padding = [0 0 0 0];

uilabel(left, 'Text', 'Plugins', 'FontWeight', 'bold');
tbl = uitable(left);
tbl.ColumnName = {'Name', 'Type', 'Root'};
tbl.ColumnWidth = {120, 80, 140};
tbl.RowName = {};
tbl.Data = localTableData(plugins);

bar = uigridlayout(left, [1 2]);
bar.ColumnWidth = {'1x', 110};
bar.Padding = [0 0 0 0];
status = uilabel(bar, 'Text', sprintf('%d plugin(s)', numel(plugins)));
uibutton(bar, 'Text', 'Refresh', 'ButtonPushedFcn', @refreshPlugins);

right = uigridlayout(main, [5 1]);
right.RowHeight = {30, 120, '1x', 190, 34};
right.ColumnWidth = {'1x'};
right.Padding = [0 0 0 0];
right.RowSpacing = 10;

titleLabel = uilabel(right, 'Text', 'Select a plugin', 'FontWeight', 'bold', 'FontSize', 15);
summaryBox = localLabeledTextArea(right, 'Business description');

middle = uigridlayout(right, [1 3]);
middle.ColumnWidth = {'1x', '1x', '1x'};
middle.RowHeight = {'1x'};
middle.Padding = [0 0 0 0];
middle.ColumnSpacing = 10;
contractBox = localLabeledTextArea(middle, 'Prerequisites / behavior');
ioBox = localLabeledTextArea(middle, 'Ports / resources');
paramsBox = localLabeledTextArea(middle, 'Parameters');

codeBox = localLabeledTextArea(right, 'Code and manifest');
buttonRow = uigridlayout(right, [1 4]);
buttonRow.ColumnWidth = {130, 130, 130, '1x'};
buttonRow.Padding = [0 0 0 0];
openFolderButton = uibutton(buttonRow, 'Text', 'Open folder', 'Enable', 'off', 'ButtonPushedFcn', @openSelectedFolder);
openReadmeButton = uibutton(buttonRow, 'Text', 'Open README', 'Enable', 'off', 'ButtonPushedFcn', @openSelectedReadme);
copyPathButton = uibutton(buttonRow, 'Text', 'Copy path', 'Enable', 'off', 'ButtonPushedFcn', @copySelectedPath);
uilabel(buttonRow, 'Text', '');

tbl.SelectionChangedFcn = @selectionChanged;
if ~isempty(plugins)
    tbl.Selection = [1 1];
    renderPlugin(1);
end

    function refreshPlugins(~, ~)
        plugins = localDiscoverPlugins(opts.Roots);
        tbl.Data = localTableData(plugins);
        status.Text = sprintf('%d plugin(s)', numel(plugins));
        if isempty(plugins)
            tbl.Selection = [];
            renderEmpty();
        else
            tbl.Selection = [1 1];
            renderPlugin(1);
        end
    end

    function selectionChanged(~, event)
        row = [];
        try
            if ~isempty(event.Selection)
                row = event.Selection(1, 1);
            end
        catch
            try
                if ~isempty(tbl.Selection)
                    row = tbl.Selection(1, 1);
                end
            catch
            end
        end
        if isempty(row) || row < 1 || row > numel(plugins)
            renderEmpty();
            return;
        end
        renderPlugin(row);
    end

    function renderEmpty()
        titleLabel.Text = 'No plugin selected';
        summaryBox.Value = {'No external plugin was found.'};
        contractBox.Value = {''};
        ioBox.Value = {''};
        paramsBox.Value = {''};
        codeBox.Value = {''};
        openFolderButton.Enable = 'off';
        openReadmeButton.Enable = 'off';
        copyPathButton.Enable = 'off';
    end

    function renderPlugin(row)
        p = plugins(row);
        titleLabel.Text = sprintf('%s (%s)', p.name, p.type);
        summaryBox.Value = localSummaryLines(p);
        contractBox.Value = localContractLines(p);
        ioBox.Value = localIoLines(p);
        paramsBox.Value = localParamLines(p);
        codeBox.Value = localCodeLines(p);
        openFolderButton.Enable = 'on';
        copyPathButton.Enable = 'on';
        if isfile(fullfile(p.path, 'README.md'))
            openReadmeButton.Enable = 'on';
        else
            openReadmeButton.Enable = 'off';
        end
    end

    function p = selectedPlugin()
        p = [];
        try
            row = tbl.Selection(1, 1);
            if row >= 1 && row <= numel(plugins)
                p = plugins(row);
            end
        catch
        end
    end

    function openSelectedFolder(~, ~)
        p = selectedPlugin();
        if isempty(p), return; end
        localOpenPath(p.path);
    end

    function openSelectedReadme(~, ~)
        p = selectedPlugin();
        if isempty(p), return; end
        readmePath = fullfile(p.path, 'README.md');
        if isfile(readmePath)
            localOpenPath(readmePath);
        end
    end

    function copySelectedPath(~, ~)
        p = selectedPlugin();
        if isempty(p), return; end
        clipboard('copy', p.path);
        status.Text = ['Copied: ' p.path];
    end
end

function opts = localParseInputs(varargin)
opts = struct('Roots', {{}});
if mod(numel(varargin), 2) ~= 0
    error('detecdiv_plugins_browser:BadInputs', 'Use name/value inputs.');
end
for i = 1:2:numel(varargin)
    key = lower(char(string(varargin{i})));
    switch key
        case 'roots'
            opts.Roots = cellstr(string(varargin{i+1}));
        otherwise
            error('detecdiv_plugins_browser:BadInput', 'Unknown option: %s', key);
    end
end
end

function plugins = localDiscoverPlugins(roots)
if isempty(roots) && exist('detecdiv_plugins_list', 'file') == 2
    try
        plugins = detecdiv_plugins_list();
        plugins = localAttachSpecs(plugins);
        return;
    catch
    end
end

if isempty(roots)
    roots = {fileparts(mfilename('fullpath'))};
end

plugins = struct('name', {}, 'type', {}, 'root', {}, 'path', {}, ...
    'entrypoint', {}, 'manifest', {}, 'summary', {}, 'spec', {});
for i = 1:numel(roots)
    plugins = [plugins, localDiscoverType(roots{i}, 'processor')]; %#ok<AGROW>
    plugins = [plugins, localDiscoverType(roots{i}, 'classifier')]; %#ok<AGROW>
end
end

function plugins = localDiscoverType(repoRoot, typeName)
plugins = struct('name', {}, 'type', {}, 'root', {}, 'path', {}, ...
    'entrypoint', {}, 'manifest', {}, 'summary', {}, 'spec', {});
parentDir = fullfile(repoRoot, 'plugins', typeName);
if ~isfolder(parentDir)
    return;
end

dirs = dir(fullfile(parentDir, '+*'));
dirs = dirs([dirs.isdir]);
[~, idx] = sort({dirs.name});
dirs = dirs(idx);
for i = 1:numel(dirs)
    pkg = erase(dirs(i).name, '+');
    pkgDir = fullfile(parentDir, dirs(i).name);
    manifest = localReadManifest(fullfile(pkgDir, 'plugin.json'));
    entrypoint = localEntrypoint(pkg, typeName, manifest);
    if isempty(entrypoint)
        continue;
    end
    summary = ['Plugin ' typeName ' package: ' pkg];
    if isstruct(manifest) && isfield(manifest, 'summary') && ~isempty(manifest.summary)
        summary = char(string(manifest.summary));
    end
    plugins(end+1) = struct( ... %#ok<AGROW>
        'name', char(string(pkg)), ...
        'type', char(string(typeName)), ...
        'root', char(string(parentDir)), ...
        'path', char(string(pkgDir)), ...
        'entrypoint', char(string(entrypoint)), ...
        'manifest', manifest, ...
        'summary', char(string(summary)), ...
        'spec', localLoadSpec(parentDir, pkg));
end
end

function plugins = localAttachSpecs(plugins)
for i = 1:numel(plugins)
    if ~isfield(plugins, 'spec') || isempty(localGetField(plugins(i), 'spec', []))
        plugins(i).spec = localLoadSpec(plugins(i).root, plugins(i).name);
    end
end
end

function manifest = localReadManifest(pathStr)
manifest = struct();
if ~isfile(pathStr)
    return;
end
try
    manifest = jsondecode(fileread(pathStr));
catch
    manifest = struct();
end
end

function entrypoint = localEntrypoint(pkg, typeName, manifest)
entrypoint = '';
if isstruct(manifest) && isfield(manifest, 'entrypoint') && ~isempty(manifest.entrypoint)
    entrypoint = char(string(manifest.entrypoint));
    return;
end
switch lower(typeName)
    case 'processor'
        entrypoint = [pkg '.process'];
    case 'classifier'
        entrypoint = [pkg '.classify'];
end
end

function spec = localLoadSpec(parentDir, pkg)
spec = struct();
if isfolder(parentDir) && ~contains(path, parentDir)
    addpath(parentDir);
end
rehash;
try
    f = [pkg '.executionSpec'];
    spec = feval(f);
catch ME
    spec = struct('error', ME.message);
end
end

function txt = localLabeledTextArea(parent, labelText)
panel = uigridlayout(parent, [2 1]);
panel.RowHeight = {22, '1x'};
panel.ColumnWidth = {'1x'};
panel.Padding = [0 0 0 0];
panel.RowSpacing = 3;
uilabel(panel, 'Text', labelText, 'FontWeight', 'bold');
txt = uitextarea(panel, 'Editable', 'off', 'Value', {labelText});
end

function data = localTableData(plugins)
data = cell(numel(plugins), 3);
for i = 1:numel(plugins)
    data{i,1} = plugins(i).name;
    data{i,2} = plugins(i).type;
    data{i,3} = plugins(i).root;
end
end

function lines = localSummaryLines(p)
lines = {
    ['Name: ' p.name]
    ['Type: ' p.type]
    ['Entrypoint: ' p.entrypoint]
    ['Folder: ' p.path]
    ''
    char(string(p.summary))
    };
if isfield(p.spec, 'summary') && ~isempty(p.spec.summary)
    lines{end+1} = '';
    lines{end+1} = 'Execution summary:';
    lines{end+1} = char(string(p.spec.summary));
end
end

function lines = localIoLines(p)
lines = {};
if isfield(p.spec, 'contract') && isstruct(p.spec.contract)
    c = p.spec.contract;
    lines = [lines; {'Input ports:'}; localColumn(localPortLines(localGetField(c, 'in', [])))]; %#ok<AGROW>
    lines = [lines; {''; 'Output ports:'}; localColumn(localPortLines(localGetField(c, 'out', [])))]; %#ok<AGROW>
    resources = localGetField(c, 'resources', struct());
    if isstruct(resources)
        lines = [lines; {''; 'Input resources:'}; localColumn(localResourceLines(localGetField(resources, 'in', [])))]; %#ok<AGROW>
        lines = [lines; {''; 'Output resources:'}; localColumn(localResourceLines(localGetField(resources, 'out', [])))]; %#ok<AGROW>
    end
else
    lines = {'No executionSpec.contract found.'};
end
end

function lines = localContractLines(p)
lines = {};
if ~isfield(p.spec, 'contract') || ~isstruct(p.spec.contract)
    lines = {'No executionSpec.contract found.'};
    return;
end

c = p.spec.contract;
if isfield(c, 'summary') && ~isempty(c.summary)
    lines = [lines; {'Summary:'; char(string(c.summary)); ''}]; %#ok<AGROW>
end

requirements = localGetField(c, 'requirements', struct());
lines = [lines; {'Prerequisites:'}; localColumn(localRequirementLines(requirements))]; %#ok<AGROW>

binding = localGetField(c, 'binding', struct());
lines = [lines; {''; 'Binding / resolution:'}; localColumn(localStructTreeLines(binding, '- '))]; %#ok<AGROW>

selectors = localGetField(c, 'selectors', struct());
lines = [lines; {''; 'Selectors / output naming:'}; localColumn(localStructTreeLines(selectors, '- '))]; %#ok<AGROW>

capabilities = localGetField(c, 'capabilities', struct());
lines = [lines; {''; 'Capabilities:'}; localColumn(localStructTreeLines(capabilities, '- '))]; %#ok<AGROW>
end

function lines = localParamLines(p)
lines = {};
if isfield(p.spec, 'contract') && isstruct(p.spec.contract) && ...
        isfield(p.spec.contract, 'parameters') && isstruct(p.spec.contract.parameters)
    lines = [lines; {'Contract parameter groups:'}; localColumn(localStructTreeLines(p.spec.contract.parameters, '- '))]; %#ok<AGROW>
end
if isfield(p.spec, 'staticKeys')
    lines = [lines; {''; 'Static parameters:'}; localColumn(localCellLines(p.spec.staticKeys))]; %#ok<AGROW>
end
if isfield(p.spec, 'outputKeys')
    lines = [lines; {''; 'Output parameters:'}; localColumn(localCellLines(p.spec.outputKeys))]; %#ok<AGROW>
end
if isfield(p.spec, 'defaults') && isstruct(p.spec.defaults)
    lines = [lines; {''; 'Defaults:'}; localColumn(localStructValueLines(p.spec.defaults))]; %#ok<AGROW>
end
if isempty(lines)
    lines = {'No parameter metadata found.'};
end
end

function lines = localCodeLines(p)
lines = {
    ['Package folder: ' p.path]
    ['Package root on MATLAB path: ' p.root]
    };
manifestPath = fullfile(p.path, 'plugin.json');
if isfile(manifestPath)
    lines{end+1} = ['Manifest: ' manifestPath];
end
readmePath = fullfile(p.path, 'README.md');
if isfile(readmePath)
    lines{end+1} = ['README: ' readmePath];
end
files = dir(fullfile(p.path, '*.m'));
if ~isempty(files)
    lines{end+1} = '';
    lines{end+1} = 'MATLAB files:';
    for i = 1:numel(files)
        lines{end+1} = ['- ' files(i).name]; %#ok<AGROW>
    end
end
end

function lines = localPortLines(ports)
if isempty(ports)
    lines = {'- none declared'};
    return;
end
lines = {};
for i = 1:numel(ports)
    item = ports(i);
    name = localGetField(item, 'name', '');
    type = localGetField(item, 'type', '');
    required = localGetField(item, 'required', false);
    source = localGetField(item, 'source', '');
    lines{end+1} = sprintf('- %s : %s | required=%s | source=%s', ...
        char(string(name)), char(string(type)), mat2str(logical(required)), char(string(source))); %#ok<AGROW>
end
end

function lines = localResourceLines(resources)
if isempty(resources)
    lines = {'- none declared'};
    return;
end
lines = {};
for i = 1:numel(resources)
    r = resources(i);
    type = localGetField(r, 'type', '');
    role = localGetField(r, 'role', '');
    symbol = localGetField(r, 'symbol', '');
    param = localGetField(r, 'param', '');
    port = localGetField(r, 'port', '');
    nameParam = localGetField(r, 'nameParam', '');
    required = localGetField(r, 'required', false);
    transfer = localGetField(r, 'transfer', '');
    lines{end+1} = sprintf('- %s | role=%s | symbol=%s | param=%s | port=%s | nameParam=%s | required=%s | transfer=%s', ...
        char(string(type)), char(string(role)), char(string(symbol)), char(string(param)), ...
        char(string(port)), char(string(nameParam)), mat2str(logical(required)), char(string(transfer))); %#ok<AGROW>
end
end

function lines = localRequirementLines(requirements)
if isempty(requirements) || ~isstruct(requirements) || isempty(fieldnames(requirements))
    lines = {'- none declared'};
    return;
end
lines = {};
groups = fieldnames(requirements);
for i = 1:numel(groups)
    groupName = groups{i};
    value = requirements.(groupName);
    if isstruct(value)
        lines{end+1} = ['- ' groupName ':']; %#ok<AGROW>
        nested = localStructTreeLines(value, '  - ');
        lines = [lines; localColumn(nested)]; %#ok<AGROW>
    else
        lines{end+1} = ['- ' groupName ': ' localValueToText(value)]; %#ok<AGROW>
    end
end
end

function lines = localCellLines(values)
values = cellstr(string(values));
lines = strcat('- ', values(:));
end

function out = localColumn(values)
out = cellstr(string(values));
out = out(:);
end

function lines = localStructValueLines(S)
fn = fieldnames(S);
lines = cell(numel(fn), 1);
for i = 1:numel(fn)
    val = S.(fn{i});
    lines{i} = ['- ' fn{i} ': ' localValueToText(val)];
end
end

function lines = localStructTreeLines(S, prefix)
if nargin < 2
    prefix = '- ';
end
if isempty(S) || ~isstruct(S) || isempty(fieldnames(S))
    lines = {'- none declared'};
    return;
end
lines = {};
fn = fieldnames(S);
for i = 1:numel(fn)
    key = fn{i};
    val = S.(key);
    if isstruct(val) && isscalar(val)
        lines{end+1} = [prefix key ':']; %#ok<AGROW>
        nested = localStructTreeLines(val, ['  ' prefix]);
        lines = [lines; localColumn(nested)]; %#ok<AGROW>
    else
        lines{end+1} = [prefix key ': ' localValueToText(val)]; %#ok<AGROW>
    end
end
end

function txt = localValueToText(val)
if ischar(val) || (isstring(val) && isscalar(val))
    txt = char(string(val));
elseif isnumeric(val) || islogical(val)
    txt = mat2str(val);
elseif iscell(val)
    txt = strjoin(cellstr(string(val)), ', ');
else
    txt = ['<' class(val) '>'];
end
end

function val = localGetField(S, fieldName, defaultVal)
val = defaultVal;
try
    if isstruct(S) && isfield(S, fieldName)
        val = S.(fieldName);
    end
catch
end
end

function localOpenPath(pathStr)
if ispc
    winopen(pathStr);
elseif ismac
    system(['open "' pathStr '"']);
else
    system(['xdg-open "' pathStr '" &']);
end
end
