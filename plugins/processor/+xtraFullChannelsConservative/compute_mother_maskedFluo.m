function paramout=compute_mother_maskedFluo(channelsExtract,channelSegCell,roiobj)

%  listChannels=listAvailableChannels;
%  listChannels=['N/A', listChannels];
% environment='pc' ;
% 
% if nargin==0
%     paramout=[];
%     
%      tip={'Choose the analysis method: Full: total fluorescence in ROI; oneMask: fluorescence within a mask; twoMask: fluorescence at the intersection of 2 masks; etc. ',...
%             'Name of 1st input channel  to score fluorescence',...
%             'Name of 2nd input channel  to score fluorescence',... 
%             'Name of 3rd input channel  to score fluorescence',... 
%             'Mask channel name used to get contours',...
%             'Class number used to idetnify contours for mask (defaullt:2)',...  
%             'Mask channel name #2 used to get contours',...
%             'Class number used to idetnify contours for mask #2 (defaullt:2)',...  
%             'max Pixels numbers to ...',...
%             'Post-processing?',...
%             '?',...
%             'Number of frames between 2 fluo acquisitions'};
%         
% %    paramout.method={'full','oneMask','TwoMask','volume','fociOrNot','oneMask'};
%     paramout.input_channel_name1=[listChannels listChannels{1}];
%     paramout.input_channel_name2=[listChannels listChannels{1}];
% %    paramout.input_channel_name3=[listChannels listChannels{1}];
% %    paramout.mask_channel_name1=[listChannels listChannels{1}]; 
% %    paramout.mask_channel_class1=2;
%  %   paramout.mask_channel_name2=[listChannels listChannels{1}];
%   %  paramout.mask_channel_class2=2;
%  %   paramout.kMaxPixels=20;
% %    paramout.postprocessing=true;
% %    paramout.volThresh=0;
% %    paramout.snapinc=1;
% 
% %    paramout.tip=tip;
%   
%     return;
% else
% paramout=param; 
% end
% 
% obj=roiobj;
% 
% %channelstr=paramout.input_channel_name;
% %channelID=obj.findChannelID(channelstr);
% % method=paramout.method{end};
% % postprocess=paramout.postprocessing; 
% % volThresh=paramout.volThresh;
% % snapinc=paramout.snapinc;
% 
% channelsExtract=[];
% %disp(roiobj.findChannelID(paramout.input_channel_name1));
% paramout.input_channel_name1=paramout.input_channel_name1{end};
% paramout.input_channel_name2=paramout.input_channel_name2{end};
% paramout.input_channel_name3=paramout.input_channel_name3{end};
% paramout.mask_channel_name1=paramout.mask_channel_name1{end};
% paramout.mask_channel_name2=paramout.mask_channel_name2{end};
% 
% if ~strcmp( paramout.input_channel_name1,'N/A')
% channelsExtract=[channelsExtract roiobj.findChannelID(paramout.input_channel_name1)];
% end
% 
% if ~strcmp( paramout.input_channel_name2,'N/A')
% channelsExtract=[channelsExtract roiobj.findChannelID(paramout.input_channel_name2)];
% end
% 
% if ~strcmp( paramout.input_channel_name3,'N/A')
% channelsExtract=[channelsExtract roiobj.findChannelID(paramout.input_channel_name3)];
% end
% 
% 
% 
% if numel(channelsExtract)==0 % this channel contains the segmented objects
%    disp([' These channels do not exist for this ROI ! Quitting ...']) ;
%    return;
% end
% 
% if numel(obj.image)==0
%     obj.load
% end


%%


   
    classiname= 'results_segX'; %_10042024
    classidMother= 2;
%    for r=1:numel(roiobj) %to parfor
%          roiobj.load();
%    end

%    for r=1:numel(roiobj) %to parfor
%        roiobj.load();
        vol = [];
%         channelSegCell=findChannelID(roiobj,classiname); 
       
%          channelSegCell=6; 
        %extract fluo for each given channel
        lastFrame=numel(roiobj.image(1,1,channelSegCell,:));
        
        
        roiobj.results.signal.onemask.(['from_' classiname]).volume=[];
        roiobj.results.signal.onemask.(['from_' classiname]).totalfluo=[];
        roiobj.results.signal.onemask.(['from_' classiname]).meanfluo=[];
        roiobj.results.signal.onemask.(['from_' classiname]).top20fluo=[];
     
        cinc=1;
        for c=channelsExtract
            meanbckg=[];
                %imbckg=roiobj.image(:,:,c,(lastFrame-2):lastFrame);
                imbckg=roiobj.image(:,:,c,lastFrame);
                mimbckg = uint16(mean(imbckg,4));
 
                im=roiobj.image(:,:,c,:);
                %init/reset
                maskTotal=zeros(size(im),'uint16');
                maskMother=zeros(size(im),'uint16');
                
                roiobj.results.signal.onemask.(['from_' classiname]).volume=NaN;
                roiobj.results.signal.onemask.(['from_' classiname]).totalfluo(cinc,1:lastFrame)=NaN;
                roiobj.results.signal.onemask.(['from_' classiname]).meanfluo(cinc,1:lastFrame)=NaN;
                roiobj.results.signal.onemask.(['from_' classiname]).top20fluo(cinc,1:lastFrame)=NaN;
                %=masks
                maskTotal=roiobj.image(:,:,channelSegCell,:); %mask containing all the classes
                maskMother=maskMother+uint16(maskTotal==classidMother)./classidMother;
                            
                
                %=masked image
                maskedMother=im.*maskMother - mimbckg.*maskMother;              
                              
                %=compute and store
                vol(cinc,:)=sum(maskMother,[1 2]);
                
%                 if postprocess==true
%                     if vol<volThresh
%                         vol=0;
%                     end
%                 end
                roiobj.results.signal.onemask.(['from_' classiname]).volume=vol;
                

                roiobj.results.signal.onemask.(['from_' classiname]).totalfluo(cinc,:)=sum(maskedMother,[1 2]);
%            end
%             roiobj.results.signal.onemask.(['from_' classiname]).totalfluo(cinc,:)=roiobj.results.signal.onemask.(['from_' classiname]).totalfluo(cinc,:);
%             roiobj.results.signal.onemask.(['from_' classiname]).totalfluo(cinc,   roiobj.results.signal.onemask.(['from_' classiname]).totalfluo(cinc,:)<0   )=0;
            roiobj.results.signal.onemask.(['from_' classiname]).meanfluo(cinc,:)=roiobj.results.signal.onemask.(['from_' classiname]).totalfluo(cinc,:)./vol(cinc,:);
                for fr = 1:lastFrame%numel(roiobj.image(1,1,c,:))
                kMaxPix = 20;%round(vol(cinc,fr)*0.7);
                roiobj.results.signal.onemask.(['from_' classiname]).top20fluo(cinc,fr)=sum(maxk( reshape(maskedMother(:,:,1,fr),[],1) ,kMaxPix));%./vol(cinc,fr);        
                end            

            cinc=cinc+1;
        end
        
         roiobj.save('results');
%      roiobj.clear;
        %clear im
%    end

% for r=1:numel(roiobj) 
%         roiobj.clear;
%   end

end
