function [pipe, report] = detecdiv_pombe_septum_relink(pipelinePath, pluginRepoRoot, varargin)
%DETECDIV_POMBE_SEPTUM_RELINK Bind a pipeline to the installed Git plugin.
% detecdiv_pombe_septum_relink('C:/path/to/pipeline/pipeline.json')
% Saves a template backup. Does not change ROI data or old run records.
if nargin<2 || isempty(pluginRepoRoot),pluginRepoRoot=fileparts(mfilename('fullpath'));end
ip=inputParser;ip.addParameter('Register',true,@(x)islogical(x)&&isscalar(x));ip.parse(varargin{:});
if nargin<1 || isempty(pipelinePath)
    [file,folder]=uigetfile('*.json','Select the pipeline template to relink');
    if isequal(file,0),pipe=[];report=struct();return;end
    pipelinePath=fullfile(folder,file);
end
processorRoot=fullfile(char(string(pluginRepoRoot)),'plugins','processor');
packageDir=fullfile(processorRoot,'+detectViterbiPombeDivisionFrame');
assert(isfile(fullfile(packageDir,'exportSeptumMosaic.m')), ...
    'Update DetecDiv-plugins from GitHub first: the septum QC exporter is missing.');
processorRoot=char(java.io.File(processorRoot).getCanonicalPath());
packageDir=char(java.io.File(packageDir).getCanonicalPath());
if ip.Results.Register,detecdiv_plugins_register_root(pluginRepoRoot);end
addpath(processorRoot,'-begin');
clear('detectViterbiPombeDivisionFrame.process','detectViterbiPombeDivisionFrame.core', ...
    'detectViterbiPombeDivisionFrame.setparam','detectViterbiPombeDivisionFrame.executionSpec', ...
    'detectViterbiPombeDivisionFrame.scoreTransverseSeptum','detectViterbiPombeDivisionFrame.exportSeptumMosaic');
rehash;
actual=which('detectViterbiPombeDivisionFrame.process');
assert(strcmpi(fileparts(actual),packageDir),'MATLAB still resolves a different plugin copy: %s',actual);
[pipe,msg]=pipelineLoad(pipelinePath);assert(isa(pipe,'pipeline'),'%s',msg);
selected=false(1,numel(pipe.nodes));
for i=1:numel(pipe.nodes)
    n=pipe.nodes(i);signature=[char(string(n.pkg)) ' ' char(string(n.func))];
    selected(i)=contains(lower(signature),'detectviterbipombedivisionframe');
end
assert(any(selected),'No Pombe septum processor in this template.');
templateFile=fullfile(pipe.path,'pipeline.json');
backup=[templateFile '.before_plugin_relink_' datestr(now,'yyyymmdd_HHMMSSFFF')];
copyfile(templateFile,backup);
defaults=detectViterbiPombeDivisionFrame.setparam();
for i=find(selected)
    previous=pipe.nodes(i).params;p=defaults;fields=fieldnames(previous);
    for k=1:numel(fields)
        if ~strcmp(fields{k},'tip'),p.(fields{k})=previous.(fields{k});end
    end
    p.septumMethod='transverse2d';p.pkg='detectViterbiPombeDivisionFrame';
    if isfield(p,'customPackageRoot'),p.customPackageRoot=processorRoot;end
    if isfield(p,'customPackageDir'),p.customPackageDir=packageDir;end
    pipe.nodes(i).params=p;pipe.nodes(i).pkg=p.pkg;
    pipe.nodes(i).func='detectViterbiPombeDivisionFrame.process';
    pipe.nodes(i).customPackageRoot=processorRoot;pipe.nodes(i).customPackageDir=packageDir;
    pipe.nodes(i).customPackageLoadedAt=char(datetime('now'));
end
nodeIds={pipe.nodes(selected).id};
pipe.runProfiles=updateOverrides(pipe.runProfiles,nodeIds,processorRoot,packageDir);
pipelineSave(pipe,'Artifacts',false);
metadata=jsondecode(fileread(fullfile(packageDir,'plugin.json')));
report=struct('template',templateFile,'backup',backup,'pluginVersion',metadata.version, ...
    'method','transverse2d','processPath',actual,'nodeIds',{nodeIds});
fprintf('Relinked %d node(s) to plugin v%s: %s\n',nnz(selected),metadata.version,actual);
fprintf('Create a NEW pipelineRun from this template. Previous template: %s\n',backup);
end

function s=updateOverrides(s,nodeIds,root,packageDir)
if ~isstruct(s),return;end
for ix=1:numel(s)
    if isfield(s(ix),'nodeParams') && isstruct(s(ix).nodeParams)
        for i=1:numel(nodeIds)
            id=nodeIds{i};
            if isfield(s(ix).nodeParams,id)
                p=s(ix).nodeParams.(id);
                if isstruct(p)
                    p.septumMethod='transverse2d';
                    if isfield(p,'customPackageRoot'),p.customPackageRoot=root;end
                    if isfield(p,'customPackageDir'),p.customPackageDir=packageDir;end
                    s(ix).nodeParams.(id)=p;
                end
            end
        end
    end
    fields=fieldnames(s(ix));
    for k=1:numel(fields)
        if ~strcmp(fields{k},'nodeParams') && isstruct(s(ix).(fields{k}))
            s(ix).(fields{k})=updateOverrides(s(ix).(fields{k}),nodeIds,root,packageDir);
        end
    end
end
end
