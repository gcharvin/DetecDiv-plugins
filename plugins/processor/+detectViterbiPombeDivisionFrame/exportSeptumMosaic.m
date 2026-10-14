function outputPath = exportSeptumMosaic(rois, summary, param, outputPath, fovId)
%EXPORTSEPTUMMOSAIC One QC tile per ROI at its first accepted septum frame.
% Reads channels without changing ROI in-memory image/channel mappings.
if isempty(rois), outputPath='';return;end
n=numel(rois);cols=min(6,n);rows=ceil(n/cols);
fig=figure('Visible','off','Color','w','Position',[50 50 340*cols 300*rows+70]);
cleanup=onCleanup(@() close(fig)); %#ok<NASGU>
layout=tiledlayout(fig,rows,cols,'Padding','compact','TileSpacing','compact');
title(layout,sprintf('%s | first detected septum | target: orange; other cells: light gray',fovId), ...
    'Interpreter','none','FontSize',11);
rawName=choice(param.rawChannelName);instanceName=choice(param.instanceChannelName);
maskName=char(string(param.outputMaskChannelName));
tiles=struct('roi',{},'frame',{},'appearanceFrame',{},'peakFrame',{},'status',{});
for i=1:n
    r=rois(i);row=summary(string(summary.ROI)==string(r.id),:);
    ds=r.data(strcmp({r.data.groupid},char(string(param.scoreSeriesName))));
    frame=row.SeptumAppearanceFrame;
    if ~isfinite(frame)
        if ~isempty(ds)
            valid=logical(ds(1).data.trackValid);
            if any(valid),frame=ds(1).data.frame(find(valid,1));end
        end
        if ~isfinite(frame),frame=1;end
    end
    ax=nexttile(layout,i);
    [raw,instances,target]=readFrame(r,rawName,instanceName,maskName,frame);
    rgb=segmentationOverlay(raw,instances,target);
    image(ax,rgb);axis(ax,'image');axis(ax,'off');
    if isfinite(row.SeptumAppearanceFrame)
        caption=sprintf('%s | onset %g | peak %g',r.id,row.SeptumAppearanceFrame,row.SeptumPeakFrame);
    else
        caption=sprintf('%s | %s | reference frame %g',r.id,char(string(row.DetectionStatus)),frame);
    end
    title(ax,caption,'Interpreter','none','FontSize',8,'FontWeight','normal');
    tiles(end+1)=struct('roi',r.id,'frame',frame,'appearanceFrame',row.SeptumAppearanceFrame, ...
        'peakFrame',row.SeptumPeakFrame,'status',char(string(row.DetectionStatus))); %#ok<AGROW>
end
exportgraphics(fig,outputPath,'Resolution',150);
metadata=struct('fovId',fovId,'frameSelection','first_accepted_septum', ...
    'targetColor',[1 .55 0],'otherColor',[.82 .82 .82],'tiles',tiles);
fid=fopen([outputPath '.json'],'w','n','UTF-8');assert(fid>=0);
fileCleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(metadata,'PrettyPrint',true));
end

function [raw,instances,target] = readFrame(r,rawName,instanceName,maskName,frame)
imageBefore=r.image;mappingBefore=r.channelid;displayBefore=r.display;dataBefore=r.data;
cleanup=onCleanup(@() restoreROI(r,imageBefore,mappingBefore,displayBefore,dataBefore)); %#ok<NASGU>
names={rawName,instanceName,maskName};
needsLoad=isempty(r.image);
if ~needsLoad
    for k=1:numel(names)
        idx=r.findChannelID(names{k});
        needsLoad=needsLoad || isempty(idx) || any(idx>size(r.image,3));
    end
end
if needsLoad,r.load('Channel',names,'Data',false,'Silent');end
assert(frame<=size(r.image,4),'QC frame is outside ROI image stack.');
raw=double(r.image(:,:,r.findChannelID(rawName),frame));
instances=r.image(:,:,r.findChannelID(instanceName),frame);
target=r.image(:,:,r.findChannelID(maskName),frame)>0;
raw=raw(:,:,1);instances=instances(:,:,1);target=target(:,:,1);
end

function restoreROI(r,imageBefore,mappingBefore,displayBefore,dataBefore)
r.image=imageBefore;r.channelid=mappingBefore;r.display=displayBefore;r.data=dataBefore;
end

function rgb=segmentationOverlay(raw,instances,target)
lim=prctile(raw(:),[1 99]);
if lim(2)>lim(1),gray=max(0,min(1,(raw-lim(1))/(lim(2)-lim(1))));else,gray=zeros(size(raw));end
rgb=repmat(gray,1,1,3);
other=instances>0 & ~target;
% Low-opacity fills preserve the raw septum texture. Instance boundaries
% remain distinct even when adjacent segmented objects touch.
rgb=blend(rgb,other,[.82 .82 .82],.12);
edges=false(size(raw));
labels=unique(instances(:));labels(labels==0)=[];
for label=labels(:).'
    edges=edges | (bwperim(instances==label,8) & ~target);
end
rgb=blend(rgb,edges,[.86 .86 .86],.75);
rgb=blend(rgb,target,[1 .55 0],.20);
rgb=blend(rgb,bwperim(target,8),[1 .55 0],.95);
end

function rgb=blend(rgb,mask,color,alpha)
for c=1:3
    plane=rgb(:,:,c);plane(mask)=(1-alpha)*plane(mask)+alpha*color(c);rgb(:,:,c)=plane;
end
end

function result=choice(raw)
if iscell(raw),raw=raw{end};end
result=char(string(raw));
end
