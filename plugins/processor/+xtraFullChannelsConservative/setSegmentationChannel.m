function setSegmentationChannel(roiobj, labels)
% The legacy scientific function assigns segmentation to plane/channel 7.
% Replace that mapping on reruns instead of appending an eighth entry.
if numel(roiobj.channelid) ~= size(roiobj.image, 3)
    error('xtraFullChannelsConservative:InvalidChannelMapping', ...
        'ROI %s has an inconsistent image/channel mapping.', roiobj.id);
end
roiobj.image(:,:,7,:) = labels;
roiobj.channelid(7) = 7;
roiobj.display.intensity(7,:) = 0;
roiobj.display.selectedchannel(7) = 1;
roiobj.display.rgb(7,:) = 1;
roiobj.display.channel{7} = 'seg';
end
